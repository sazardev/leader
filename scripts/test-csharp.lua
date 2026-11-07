-- Tests of the C# helpers: project/solution discovery and the dotnet JSON parsers (utils/csharpproj.lua), the
-- treesitter index (utils/csharpindex.lua), the smart completion (utils/csharpsmart.lua) and the `dotnet test`
-- adapter (TRX, filters, scopes). No dotnet process, no network: every command is built and every report is parsed
-- from a string. The treesitter parts skip cleanly when the c_sharp parser is not installed.
local root = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
vim.opt.rtp:prepend(root .. "/nvim")
package.path = root .. "/nvim/lua/?.lua;" .. root .. "/nvim/lua/?/init.lua;" .. package.path

local fails, total = 0, 0
local function eq(name, got, want)
  total = total + 1
  if not vim.deep_equal(got, want) then
    fails = fails + 1
    print("FAIL " .. name)
    print("  got:  " .. vim.inspect(got))
    print("  want: " .. vim.inspect(want))
  end
end
local function ok(name, cond)
  eq(name, cond and true or false, true)
end

local base = vim.fn.tempname()
local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "w"))
  f:write(text or "")
  f:close()
end
local function has_parser(lang)
  local ok, added = pcall(vim.treesitter.language.add, lang)
  return ok and added ~= false
end
local has_csharp = has_parser "c_sharp"

-- ── project and solution helpers ─────────────────────────────────────────────

local proj = require "utils.csharpproj"
local sln_list = [[
Project(s)
----------
Lib/Lib.csproj
Tests/Tests.csproj
]]
eq("sln list: only the projects, relative as printed", proj.parse_sln_list(sln_list), { "Lib/Lib.csproj", "Tests/Tests.csproj" })

local profiles = proj.parse_launch_settings [[
{
  "profiles": {
    "https": { "commandName": "Project", "applicationUrl": "https://localhost:7001;http://localhost:5001" },
    "IIS Express": { "commandName": "IISExpress", "applicationUrl": "http://localhost:5000" }
  }
}
]]
eq("launchSettings: sorted profiles, the first URL of each", {
  { profiles[1].name, profiles[1].command, profiles[1].url },
  { profiles[2].name, profiles[2].command, profiles[2].url },
}, {
  { "IIS Express", "IISExpress", "http://localhost:5000" },
  { "https", "Project", "https://localhost:7001" },
})

local search = proj.parse_package_search [[
{"version":2,"searchResult":[{"sourceName":"nuget.org","packages":[
  {"id":"xunit","latestVersion":"2.9.3","totalDownloads":1131832300,"owners":"xunit"},
  {"id":"xunit","latestVersion":"2.9.2","totalDownloads":1}
]}]}
]]
eq("package search: the packages, the first source wins", {
  { search[1].id, search[1].version, search[1].downloads, search[1].owners },
  #search,
}, { { "xunit", "2.9.3", 1131832300, "xunit" }, 1 })

local outdated = proj.parse_outdated [[
{"version":1,"projects":[{"path":"/p/Api.csproj","frameworks":[{"framework":"net10.0",
  "topLevelPackages":[{"id":"A","requestedVersion":"1.0.0","resolvedVersion":"1.0.0","latestVersion":"2.0.0"}],
  "transitivePackages":[{"id":"B","resolvedVersion":"1.0.0","latestVersion":"1.1.0"}]}]}]}
]]
eq("outdated: direct and transitive, with the latest version", {
  { outdated[1].id, outdated[1].requested, outdated[1].latest, outdated[1].direct },
  { outdated[2].id, outdated[2].requested, outdated[2].latest, outdated[2].direct },
}, { { "A", "1.0.0", "2.0.0", true }, { "B", nil, "1.1.0", false } })

local vulnerable = proj.parse_vulnerable [[
{"version":1,"projects":[{"path":"/p/Api.csproj","frameworks":[{"framework":"net10.0","topLevelPackages":[
  {"id":"Newtonsoft.Json","requestedVersion":"12.0.1","resolvedVersion":"12.0.1",
   "vulnerabilities":[{"severity":"High","advisoryurl":"https://example.test/advisory"}]}]}]}]}
]]
eq("vulnerable: id, version, severity and advisory", {
  vulnerable[1].id,
  vulnerable[1].version,
  vulnerable[1].severity,
  vulnerable[1].advisory,
}, { "Newtonsoft.Json", "12.0.1", "High", "https://example.test/advisory" })

eq("csproj: target framework and assembly name", {
  proj.tfm '<Project><PropertyGroup><TargetFramework>net9.0</TargetFramework></PropertyGroup></Project>',
  proj.assembly('<Project><PropertyGroup><AssemblyName>Api</AssemblyName></PropertyGroup></Project>', "Fallback"),
}, { "net9.0", "Api" })
ok("csproj: a test project is recognized by Microsoft.NET.Test.Sdk", proj.is_test_project "<PackageReference Include=\"Microsoft.NET.Test.Sdk\" />")

local tree = base .. "/tree"
write(tree .. "/All.slnx", "<Solution />")
write(tree .. "/src/Api/Api.csproj", "<Project><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>")
write(tree .. "/tests/Api.Tests/Api.Tests.csproj", "<Project><ItemGroup><PackageReference Include=\"Microsoft.NET.Test.Sdk\" /></ItemGroup></Project>")
eq("root: the solution wins over the project inside it", proj.find_root(tree .. "/src/Api"), tree)
eq("projects: every .csproj under the solution", proj.projects(tree), {
  tree .. "/src/Api/Api.csproj",
  tree .. "/tests/Api.Tests/Api.Tests.csproj",
})
eq("test target: the solution when there is one", proj.test_target(tree), tree .. "/All.slnx")
eq("profiles: a project without launchSettings has none", proj.profiles(tree .. "/src/Api"), {})

-- ── treesitter index ─────────────────────────────────────────────────────────

local sample = [==[
namespace Acme.Api;
using System.Text;

public sealed class Note
{
    public int Id { get; set; }
    public string Title { get; set; } = "";
}

public interface INoteService
{
    Task<Note?> GetAsync(string id, CancellationToken ct);
}

public sealed class NoteService : INoteService
{
    private readonly INoteRepository _repository;
    private readonly ILogger<NoteService> _logger;

    public NoteService(INoteRepository repository, ILogger<NoteService> logger)
    {
        _repository = repository;
        _logger = logger;
    }

    [Fact]
    public Task<Note?> GetAsync(string id, CancellationToken ct) => _repository.FindAsync(id, ct);
}

public sealed record Order(int Id, string Number);
]==]
local index = require "utils.csharpindex"
if has_csharp then
  local info = index.scan(sample)
  eq("index: namespace and the using directives", { info.namespace, info.usings }, { "Acme.Api", { "System.Text" } })
  local by_name = {}
  for _, t in ipairs(info.types) do
    by_name[t.name] = t
  end
  eq("index: types and their kinds", {
    by_name.Note.kind,
    by_name.INoteService.kind,
    by_name.NoteService.kind,
    by_name.Order.kind,
  }, { "class", "interface", "class", "record" })
  eq("index: full names and bases", {
    by_name.NoteService.full_name,
    by_name.NoteService.base_names[1],
    by_name.NoteService.interfaces[1],
  }, { "Acme.Api.NoteService", "INoteService", "INoteService" })
  eq("index: fields and the constructor parameters", {
    by_name.NoteService.fields[1].name,
    by_name.NoteService.fields[1].type,
    by_name.NoteService.fields[1].readonly,
    by_name.NoteService.ctors[1].params[1].name,
    by_name.NoteService.ctors[1].params[1].type,
  }, { "_repository", "INoteRepository", true, "repository", "INoteRepository" })
  eq("index: a test method is marked as such", {
    by_name.NoteService.methods[1].name,
    by_name.NoteService.methods[1].test,
    by_name.NoteService.test_methods[1].name,
  }, { "GetAsync", true, "GetAsync" })
  eq("index: a record's primary constructor gives it an Id", { by_name.Order.has_id, by_name.Order.id_type }, { true, "int" })
  eq("index: an entity is a type with an Id and a name that is not a service/controller", {
    by_name.Note.has_id,
    by_name.NoteService.has_id == nil,
  }, { true, true })
else
  print "skip: no c_sharp parser"
end

-- ── smart completion ─────────────────────────────────────────────────────────

local smart = require "utils.csharpsmart"
eq("smart: file name to type", { smart.type_name "note_service.cs", smart.type_name "NoteService.cs" }, { "NoteService", "NoteService" })
eq("smart: interface name", { smart.interface_name "NoteService", smart.interface_name "INoteService" }, { "INoteService", "INoteService" })
eq("smart: plurals", { smart.plural "Note", smart.plural "Category", smart.plural "Box" }, { "Notes", "Categories", "Boxes" })

if has_csharp then
  local note = index.scan(sample).types
  local note_service
  for _, t in ipairs(note) do
    if t.name == "NoteService" then
      note_service = t
    end
  end
  eq("smart: constructor fields skip initialized/static fields", {
    smart.constructor_fields(note_service)[1].name,
    smart.constructor_fields(note_service)[1].type,
  }, { "repository", "INoteRepository" })
  local ctor = smart.constructor_text(note_service, "")
  ok("smart: constructor text takes the fields", ctor:find("public NoteService(INoteRepository repository, ILogger<NoteService> logger)", 1, true) ~= nil)
  local props = smart.property_items(note_service, "")
  eq("smart: properties from private fields", { props[1].label, props[2].label }, { "Repository", "Logger" })

  local fake = {
    entities = { { name = "Note", namespace = "Acme.Domain" }, { name = "Category", namespace = "Acme.Domain" } },
    services = {
      { name = "NoteService", namespace = "Acme.Services", interfaces = { "INoteService" } },
      { name = "NoteRepository", namespace = "Acme.Services", interfaces = { "INoteRepository" } },
    },
    by_name = {
      INoteService = { namespace = "Acme.Services" },
      INoteRepository = { namespace = "Acme.Services" },
    },
  }
  eq("smart: DbSet items for every entity, with the using", {
    smart.dbset_items(fake, nil, "Acme.Api")[1].label,
    smart.dbset_items(fake, nil, "Acme.Api")[1].text,
    smart.dbset_items(fake, nil, "Acme.Api")[1].usings[1],
  }, { "DbSet<Note> Notes", "public DbSet<Note> Notes => Set<Note>();", "Acme.Domain" })
  local di = smart.di_items(fake, "Add", "Acme.Api")
  eq("smart: DI registrations for every lifetime", {
    di[1].label,
    di[2].label,
    di[3].label,
    di[1].usings[1],
  }, { "AddScoped<INoteService, NoteService>", "AddSingleton<INoteService, NoteService>", "AddTransient<INoteService, NoteService>", "Acme.Services" })
  eq("smart: only the lifetimes the typed prefix names", {
    smart.di_items(fake, "AddS", "Acme.Api")[1].label,
    smart.di_items(fake, "AddS", "Acme.Api")[2].label,
    smart.di_items(fake, "AddS", "Acme.Api")[3].label,
  }, { "AddScoped<INoteService, NoteService>", "AddSingleton<INoteService, NoteService>", "AddScoped<INoteRepository, NoteRepository>" })
  eq("smart: declarations named after the file", smart.declaration_items("/p/NoteService.cs", "cla")[1].name, "NoteService")
end

-- ── the actual blink source ─────────────────────────────────────────────────

if has_csharp then
  local project = base .. "/smart"
  write(project .. "/Domain.cs", [==[
namespace Acme.Domain;
public sealed class Note { public int Id { get; set; } }
public interface INoteService { Task<Note?> GetAsync(int id, CancellationToken ct); }
public sealed class NoteService : INoteService
{
    public Task<Note?> GetAsync(int id, CancellationToken ct) => Task.FromResult<Note?>(null);
}
]==])
  write(project .. "/NotesController.cs", [==[
namespace Acme.Api;
public sealed class NotesController : ControllerBase
{
    private readonly INoteService _service;
    private readonly ILogger<NotesController> _logger;
    ctor
}
]==])
  write(project .. "/AppDbContext.cs", [==[
namespace Acme.Api;
public sealed class AppDbContext : DbContext
{
    dbSet
}
]==])
  write(project .. "/Program.cs", [==[
var builder = WebApplication.CreateBuilder(args);
builder.Services.Add
]==])
  write(project .. "/BrandNew.cs", "cla\n")

  local function completions(path, needle)
    vim.cmd.edit(path)
    vim.bo.filetype = "cs"
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local row
    for i, line in ipairs(lines) do
      if line:find(needle, 1, true) then
        row = i
        break
      end
    end
    assert(row, "needle not found: " .. needle)
    local line = lines[row]
    local out
    smart.new():get_completions({ bufnr = 0, cursor = { row, #line }, line = line }, function(r)
      out = r
    end)
    return vim.tbl_map(function(i)
      return i.label
    end, out.items or {})
  end

  eq("source: declarations at the top", { completions(project .. "/BrandNew.cs", "cla")[1] }, { "class BrandNew" })
  eq("source: ctor from the class fields", { completions(project .. "/NotesController.cs", "ctor")[1] }, {
    "ctor(INoteService service, ILogger<NotesController> logger)",
  })
  eq("source: DbSet suggestions in a DbContext", { completions(project .. "/AppDbContext.cs", "dbSet")[1] }, { "DbSet<Note> Notes" })
  local di = completions(project .. "/Program.cs", "builder.Services.Add")
  ok("source: DI suggestions after services.Add", di[1] ~= nil and di[1]:find("AddScoped", 1, true) ~= nil)
end

-- ── usings ───────────────────────────────────────────────────────────────────

local ubuf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(ubuf, 0, -1, false, { "namespace Acme.Api;", "", "public class A { }" })
smart.apply_usings(ubuf, { "Acme.Domain" }, "Acme.Api")
eq("usings: inserted before the namespace", vim.api.nvim_buf_get_lines(ubuf, 0, 1, false), { "using Acme.Domain;" })
smart.apply_usings(ubuf, { "Acme.Domain" }, "Acme.Api")
eq("usings: never twice", #vim.api.nvim_buf_get_lines(ubuf, 0, -1, false), 4)
vim.api.nvim_buf_delete(ubuf, { force = true })

-- ── dotnet test adapter ─────────────────────────────────────────────────────

local adapter = require "langtest.adapters.dotnet"
ok("dotnet tests: a Tests/ folder is a test file", adapter.is_test "/p/Tests/Foo.cs")
local test_file = base .. "/adapter/CalcTests.cs"
write(test_file, [==[
namespace Acme.Tests;

public sealed class CalcTests
{
    [Fact]
    public void Adds() { Assert.Equal(2, 1 + 1); }

    [Theory]
    [InlineData(1)]
    public void Positive(int value) { Assert.True(value > 0); }

    [TestMethod]
    public void Skips() { }

    public void Helper() { }
}
]==])
if has_csharp then
  vim.cmd.edit(test_file)
  vim.bo.filetype = "cs"
  local defs = adapter.tests(0)
  eq("dotnet tests: Fact, Theory and TestMethod, not helpers", {
    defs[1].id,
    defs[2].id,
    defs[3].id,
    #defs,
  }, { "Acme.Tests.CalcTests.Adds", "Acme.Tests.CalcTests.Positive", "Acme.Tests.CalcTests.Skips", 3 })
  local ctx = {
    scope = "nearest",
    root = base .. "/adapter",
    file = test_file,
    rel = "CalcTests.cs",
    test = defs[1],
    tests = defs,
    report = base .. "/adapter/out/report",
  }
  eq("dotnet tests: nearest filter", adapter.filter(ctx), "FullyQualifiedName~Acme.Tests.CalcTests.Adds")
  ctx.scope = "file"
  eq("dotnet tests: file filter groups the classes", adapter.filter(ctx), "FullyQualifiedName~Acme.Tests.CalcTests")
  ctx.scope = "all"
  eq("dotnet tests: all has no filter", adapter.filter(ctx), nil)
  ctx.scope = "file"
  ctx.tests = {}
  eq(
    "dotnet tests: a test file that is not in a buffer is read from disk",
    adapter.filter(ctx),
    "FullyQualifiedName~Acme.Tests.CalcTests"
  )
  ctx.file = base .. "/adapter/Plain.cs"
  eq(
    "dotnet tests: a source file with no tests runs none, not the whole solution",
    adapter.filter(ctx),
    "FullyQualifiedName~__no_tests_in_this_file__"
  )
  local cmd = adapter.command(ctx)
  ok("dotnet tests: the command asks dotnet test for a TRX report", vim.iter(cmd):any(function(a)
    return a == "--logger"
  end) and vim.iter(cmd):any(function(a)
    return a:find("trx;", 1, true) ~= nil
  end))
end

local trx = [==[
<?xml version="1.0" encoding="utf-8"?>
<TestRun>
  <Results>
    <UnitTestResult testId="1" testName="Acme.Tests.CalcTests.Adds" outcome="Passed" />
    <UnitTestResult testId="2" testName="Acme.Tests.CalcTests.Div" outcome="Failed">
      <Output><ErrorInfo>
        <Message>Assert.Equal() Failure: Expected 1, Actual 2</Message>
        <StackTrace>   at Acme.Tests.CalcTests.Div() in tests/CalcTests.cs:line 12</StackTrace>
      </ErrorInfo></Output>
    </UnitTestResult>
    <UnitTestResult testId="3" testName="Acme.Tests.CalcTests.Skip" outcome="NotExecuted" />
    <UnitTestResult testId="4" testName="Acme.Tests.CalcTests.Theory(value: 2)" outcome="Passed" />
  </Results>
  <TestDefinitions>
    <UnitTest name="Acme.Tests.CalcTests.Adds" id="1"><TestMethod className="Acme.Tests.CalcTests" name="Adds" /></UnitTest>
    <UnitTest name="Acme.Tests.CalcTests.Div" id="2"><TestMethod className="Acme.Tests.CalcTests" name="Div" /></UnitTest>
    <UnitTest name="Acme.Tests.CalcTests.Skip" id="3"><TestMethod className="Acme.Tests.CalcTests" name="Skip" /></UnitTest>
    <UnitTest name="Acme.Tests.CalcTests.Theory(value: 2)" id="4"><TestMethod className="Acme.Tests.CalcTests" name="Theory" /></UnitTest>
  </TestDefinitions>
</TestRun>
]==]
local results = adapter.parse_trx(trx)
local by_id = {}
for _, r in ipairs(results) do
  by_id[r.id] = r
end
eq("TRX: every result, the theory collapsed into its method", {
  by_id["Acme.Tests.CalcTests.Adds"].status,
  by_id["Acme.Tests.CalcTests.Div"].status,
  by_id["Acme.Tests.CalcTests.Div"].fail_line,
  by_id["Acme.Tests.CalcTests.Div"].message,
  by_id["Acme.Tests.CalcTests.Skip"].status,
  by_id["Acme.Tests.CalcTests.Theory"].status,
  #results,
}, { "pass", "fail", 12, "Assert.Equal() Failure: Expected 1, Actual 2", "skip", "pass", 4 })
local resolved = adapter.parse({ report = trx }, {
  root = base .. "/adapter",
  file = test_file,
  rel = "CalcTests.cs",
  tests = {},
})
local div
for _, r in ipairs(resolved) do
  if r.id:find("Div", 1, true) then
    div = r
  end
end
eq("TRX: a relative stack path is resolved against the project", div and div.file, base .. "/adapter/tests/CalcTests.cs")

vim.fn.delete(base, "rf")
print(("%d/%d passed"):format(total - fails, total))
if fails == 0 then
  print "ALL OK"
else
  print(("FAILURES: %d"):format(fails))
end
vim.cmd "qa!"
