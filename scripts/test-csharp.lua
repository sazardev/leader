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
local has_csharp = has_parser("c_sharp")

-- ── project and solution helpers ─────────────────────────────────────────────

local proj = require("utils.csharpproj")
local sln_list = [[
Project(s)
----------
Lib/Lib.csproj
Tests/Tests.csproj
]]
eq(
  "sln list: only the projects, relative as printed",
  proj.parse_sln_list(sln_list),
  { "Lib/Lib.csproj", "Tests/Tests.csproj" }
)

local profiles = proj.parse_launch_settings([[
{
  "profiles": {
    "https": { "commandName": "Project", "applicationUrl": "https://localhost:7001;http://localhost:5001" },
    "IIS Express": { "commandName": "IISExpress", "applicationUrl": "http://localhost:5000" }
  }
}
]])
eq("launchSettings: sorted profiles, the first URL of each", {
  { profiles[1].name, profiles[1].command, profiles[1].url },
  { profiles[2].name, profiles[2].command, profiles[2].url },
}, {
  { "IIS Express", "IISExpress", "http://localhost:5000" },
  { "https", "Project", "https://localhost:7001" },
})

local search = proj.parse_package_search([[
{"version":2,"searchResult":[{"sourceName":"nuget.org","packages":[
  {"id":"xunit","latestVersion":"2.9.3","totalDownloads":1131832300,"owners":"xunit"},
  {"id":"xunit","latestVersion":"2.9.2","totalDownloads":1}
]}]}
]])
eq("package search: the packages, the first source wins", {
  { search[1].id, search[1].version, search[1].downloads, search[1].owners },
  #search,
}, { { "xunit", "2.9.3", 1131832300, "xunit" }, 1 })

local outdated = proj.parse_outdated([[
{"version":1,"projects":[{"path":"/p/Api.csproj","frameworks":[{"framework":"net10.0",
  "topLevelPackages":[{"id":"A","requestedVersion":"1.0.0","resolvedVersion":"1.0.0","latestVersion":"2.0.0"}],
  "transitivePackages":[{"id":"B","resolvedVersion":"1.0.0","latestVersion":"1.1.0"}]}]}]}
]])
eq("outdated: direct and transitive, with the latest version", {
  { outdated[1].id, outdated[1].requested, outdated[1].latest, outdated[1].direct },
  { outdated[2].id, outdated[2].requested, outdated[2].latest, outdated[2].direct },
}, { { "A", "1.0.0", "2.0.0", true }, { "B", nil, "1.1.0", false } })

local vulnerable = proj.parse_vulnerable([[
{"version":1,"projects":[{"path":"/p/Api.csproj","frameworks":[{"framework":"net10.0","topLevelPackages":[
  {"id":"Newtonsoft.Json","requestedVersion":"12.0.1","resolvedVersion":"12.0.1",
   "vulnerabilities":[{"severity":"High","advisoryurl":"https://example.test/advisory"}]}]}]}]}
]])
eq("vulnerable: id, version, severity and advisory", {
  vulnerable[1].id,
  vulnerable[1].version,
  vulnerable[1].severity,
  vulnerable[1].advisory,
}, { "Newtonsoft.Json", "12.0.1", "High", "https://example.test/advisory" })

eq("csproj: target framework and assembly name", {
  proj.tfm("<Project><PropertyGroup><TargetFramework>net9.0</TargetFramework></PropertyGroup></Project>"),
  proj.assembly("<Project><PropertyGroup><AssemblyName>Api</AssemblyName></PropertyGroup></Project>", "Fallback"),
}, { "net9.0", "Api" })
ok(
  "csproj: a test project is recognized by Microsoft.NET.Test.Sdk",
  proj.is_test_project('<PackageReference Include="Microsoft.NET.Test.Sdk" />')
)

local tree = base .. "/tree"
write(tree .. "/All.slnx", "<Solution />")
write(
  tree .. "/src/Api/Api.csproj",
  "<Project><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>"
)
write(
  tree .. "/tests/Api.Tests/Api.Tests.csproj",
  '<Project><ItemGroup><PackageReference Include="Microsoft.NET.Test.Sdk" /></ItemGroup></Project>'
)
eq("root: the solution wins over the project inside it", proj.find_root(tree .. "/src/Api"), tree)
eq("projects: every .csproj under the solution", proj.projects(tree), {
  tree .. "/src/Api/Api.csproj",
  tree .. "/tests/Api.Tests/Api.Tests.csproj",
})
eq("test target: the solution when there is one", proj.test_target(tree), tree .. "/All.slnx")
eq("profiles: a project without launchSettings has none", proj.profiles(tree .. "/src/Api"), {})

-- ── Unity ───────────────────────────────────────────────────────────────────

local unity = base .. "/unity"
write(unity .. "/Assets/Game/Player.cs", "public class Player {}")
write(unity .. "/ProjectSettings/ProjectVersion.txt", "m_EditorVersion: 6000.0.0f1")
eq("unity: Assets/ + ProjectSettings/ is a Unity root", proj.is_unity(unity), true)
eq("unity: the root is found upwards from a script", proj.unity_root(unity .. "/Assets/Game"), unity)
eq("unity: not a Unity root without the folders", proj.is_unity(tree), false)
eq("unity: find_root falls back to ProjectSettings/", proj.find_root(unity .. "/Assets/Game"), unity)
-- Library/ is Unity-generated: it never holds a .csproj
write(unity .. "/Library/PackageCache/Helper.csproj", "<Project />")
eq("unity: generated folders are skipped when listing projects", proj.projects(unity), {})

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
local index = require("utils.csharpindex")
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
  eq(
    "index: a record's primary constructor gives it an Id",
    { by_name.Order.has_id, by_name.Order.id_type },
    { true, "int" }
  )
  eq("index: an entity is a type with an Id and a name that is not a service/controller", {
    by_name.Note.has_id,
    by_name.NoteService.has_id == nil,
  }, { true, true })
else
  print("skip: no c_sharp parser")
end

-- ── smart completion ─────────────────────────────────────────────────────────

local smart = require("utils.csharpsmart")
eq(
  "smart: file name to type",
  { smart.type_name("note_service.cs"), smart.type_name("NoteService.cs") },
  { "NoteService", "NoteService" }
)
eq(
  "smart: interface name",
  { smart.interface_name("NoteService"), smart.interface_name("INoteService") },
  { "INoteService", "INoteService" }
)
eq(
  "smart: plurals",
  { smart.plural("Note"), smart.plural("Category"), smart.plural("Box") },
  { "Notes", "Categories", "Boxes" }
)

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
  ok(
    "smart: constructor text takes the fields",
    ctor:find("public NoteService(INoteRepository repository, ILogger<NoteService> logger)", 1, true) ~= nil
  )
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
  eq(
    "smart: DI registrations for every lifetime",
    {
      di[1].label,
      di[2].label,
      di[3].label,
      di[1].usings[1],
    },
    {
      "AddScoped<INoteService, NoteService>",
      "AddSingleton<INoteService, NoteService>",
      "AddTransient<INoteService, NoteService>",
      "Acme.Services",
    }
  )
  eq(
    "smart: only the lifetimes the typed prefix names",
    {
      smart.di_items(fake, "AddS", "Acme.Api")[1].label,
      smart.di_items(fake, "AddS", "Acme.Api")[2].label,
      smart.di_items(fake, "AddS", "Acme.Api")[3].label,
    },
    {
      "AddScoped<INoteService, NoteService>",
      "AddSingleton<INoteService, NoteService>",
      "AddScoped<INoteRepository, NoteRepository>",
    }
  )
  eq(
    "smart: declarations named after the file",
    smart.declaration_items("/p/NoteService.cs", "cla")[1].name,
    "NoteService"
  )
end

-- ── the actual blink source ─────────────────────────────────────────────────

if has_csharp then
  local project = base .. "/smart"
  write(
    project .. "/Domain.cs",
    [==[
namespace Acme.Domain;
public sealed class Note { public int Id { get; set; } }
public interface INoteService { Task<Note?> GetAsync(int id, CancellationToken ct); }
public sealed class NoteService : INoteService
{
    public Task<Note?> GetAsync(int id, CancellationToken ct) => Task.FromResult<Note?>(null);
}
]==]
  )
  write(
    project .. "/NotesController.cs",
    [==[
namespace Acme.Api;
public sealed class NotesController : ControllerBase
{
    private readonly INoteService _service;
    private readonly ILogger<NotesController> _logger;
    ctor
}
]==]
  )
  write(
    project .. "/AppDbContext.cs",
    [==[
namespace Acme.Api;
public sealed class AppDbContext : DbContext
{
    dbSet
}
]==]
  )
  write(
    project .. "/Program.cs",
    [==[
var builder = WebApplication.CreateBuilder(args);
builder.Services.Add
]==]
  )
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
  eq(
    "source: DbSet suggestions in a DbContext",
    { completions(project .. "/AppDbContext.cs", "dbSet")[1] },
    { "DbSet<Note> Notes" }
  )
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

local adapter = require("langtest.adapters.dotnet")
ok("dotnet tests: a Tests/ folder is a test file", adapter.is_test("/p/Tests/Foo.cs"))
local test_file = base .. "/adapter/CalcTests.cs"
write(
  test_file,
  [==[
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
]==]
)
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
eq(
  "TRX: a relative stack path is resolved against the project",
  div and div.file,
  base .. "/adapter/tests/CalcTests.cs"
)

-- ── Solution Explorer model ─────────────────────────────────────────────────

eq("tfms: one, several, and the fallback", {
  proj.tfms("<Project><PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup></Project>")[1],
  table.concat(
    proj.tfms("<Project><PropertyGroup><TargetFrameworks>net10.0;net8.0</TargetFrameworks></PropertyGroup></Project>"),
    ","
  ),
  proj.tfms("<Project />")[1],
}, { "net8.0", "net10.0,net8.0", "net10.0" })
eq("csproj info: sdk, output kind, refs and packages", {
  proj.sdk('<Project Sdk="Microsoft.NET.Sdk.Web">'),
  proj.output_type('<Project Sdk="Microsoft.NET.Sdk.Web" />'),
  proj.output_type("<Project><PropertyGroup><OutputType>Exe</OutputType></PropertyGroup></Project>"),
  proj.output_type("<Project><PropertyGroup><OutputType>Library</OutputType></PropertyGroup></Project>"),
  proj.project_refs('<Project><ItemGroup><ProjectReference Include="..\\Domain\\Domain.csproj" /><ProjectReference Include="../A/A.csproj" /></ItemGroup></Project>'),
  proj.package_refs('<Project><ItemGroup><PackageReference Include="Serilog.AspNetCore" Version="9.0.0" /><PackageReference Include="Xunit" VersionOverride="2.9.3" /></ItemGroup></Project>'),
}, {
  "Microsoft.NET.Sdk.Web",
  "Exe",
  "Exe",
  "Library",
  { "../A/A.csproj", "..\\Domain\\Domain.csproj" },
  { { id = "Serilog.AspNetCore", version = "9.0.0" }, { id = "Xunit", version = "2.9.3" } },
})

local sln = [[
Microsoft Visual Studio Solution File, Format Version 12.00
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Api", "src\Api\Api.csproj", "{11111111-1111-1111-1111-111111111111}"
EndProject
Project("{2150E333-8FDC-42A3-9474-1A3956D46DE8}") = "src", "src", "{22222222-2222-2222-2222-222222222222}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Domain", "src\Domain\Domain.csproj", "{33333333-3333-3333-3333-333333333333}"
EndProject
]]
local parsed_sln = proj.parse_sln(sln)
eq("sln: projects and the solution folder, backslashes kept", {
  { parsed_sln[1].name, parsed_sln[1].kind },
  { parsed_sln[2].name, parsed_sln[2].kind },
  { parsed_sln[3].name, parsed_sln[3].path },
}, { { "Api", "project" }, { "src", "folder" }, { "Domain", "src\\Domain\\Domain.csproj" } })
eq(
  "slnx: Project Path and Folder Name",
  vim.tbl_map(function(p)
    return { p.name, p.kind }
  end, proj.parse_slnx('<Solution><Project Path="src/Api/Api.csproj" /><Folder Name="tests" /></Solution>')),
  { { "Api", "project" }, { "tests", "folder" } }
)

local sln_root = base .. "/sln"
write(sln_root .. "/App.sln", sln)
write(
  sln_root .. "/src/Api/Api.csproj",
  '<Project Sdk="Microsoft.NET.Sdk.Web"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup><ItemGroup><ProjectReference Include="..\\Domain\\Domain.csproj" /><PackageReference Include="Serilog.AspNetCore" Version="9.0.0" /></ItemGroup></Project>'
)
write(
  sln_root .. "/src/Domain/Domain.csproj",
  '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework><OutputType>Library</OutputType></PropertyGroup></Project>'
)
local solution = require("utils.csharpsolution")
local smodel = solution.model(sln_root, sln_root .. "/App.sln")
eq(
  "explorer: grouping by first folder, root last",
  vim.tbl_map(function(g)
    return { g.name, #g.projects }
  end, smodel.groups),
  { { "src", 2 } }
)
local api = smodel.projects[1]
if smodel.projects[2] and smodel.projects[2].name == "Api" then
  api = smodel.projects[2]
end
eq("explorer: dependencies resolved by project name, packages counted", {
  api.name,
  table.concat(api.tfms, ","),
  api.output,
  table.concat(api.dependencies, ","),
  #api.packages,
}, { "Api", "net10.0", "Exe", "Domain", 1 })
eq("explorer: rows have the title, the group and one row per project", {
  #solution.rows(smodel),
  solution.rows(smodel)[3].group,
  solution.rows(smodel)[4].project.name,
}, { 6, "src", "Api" })
ok(
  "explorer: detail names the TFM and the dependency",
  table.concat(solution.detail(smodel, api), "\n"):find("net10.0", 1, true) ~= nil
    and table.concat(solution.detail(smodel, api), "\n"):find("Domain", 1, true) ~= nil
)

-- ── Run configurations ──────────────────────────────────────────────────────

local runcfg = require("utils.csharprun")
eq("run: docker when only a Dockerfile, compose when only compose", {
  (runcfg.docker("/p", true, false) or {}).kind,
  (runcfg.docker("/p", false, true) or {}).kind,
  runcfg.docker("/p", false, false),
}, { "docker", "compose", nil })
local run_projects = {
  { name = "Api", path = "/r/src/Api/Api.csproj" },
  { name = "Tests", path = "/r/tests/Tests/Tests.csproj" },
}
-- no launchSettings on disk: one dotnet config per project
eq(
  "run: one config per project without profiles",
  vim.tbl_map(function(c)
    return { c.name, c.kind }
  end, runcfg.build("/r", run_projects, {}, nil)),
  { { "Api", "dotnet" }, { "Tests", "dotnet" } }
)
local saved = { { name = "Quick", kind = "custom", command = "echo hi", root = "/r" } }
local built = runcfg.build("/r", run_projects, saved, runcfg.docker("/r", true, false))
eq("run: saved and docker are appended", { #built, built[3].kind, built[4].name }, { 4, "docker", "Quick" })
eq("run: the command of each kind", {
  runcfg.command({ kind = "dotnet", project = "/r/src/Api/Api.csproj", profile = "https" }),
  runcfg.command({ kind = "docker", dockerfile = "/r/Dockerfile" }),
  runcfg.command({ kind = "compose", compose = "/r/docker-compose.yml", service = "api" }),
  runcfg.command({ kind = "custom", command = "echo hi" }),
  runcfg.command({ kind = "compound", targets = { { command = "dotnet build" }, { command = "dotnet run" } } }),
  runcfg.command(nil),
}, {
  "dotnet run --project '/r/src/Api/Api.csproj' --launch-profile 'https'",
  "docker build -t 'r' -f '/r/Dockerfile' '/r' && docker run --rm -p 8080:8080 'r'",
  "docker compose -f '/r/docker-compose.yml' up --build 'api'",
  "echo hi",
  "dotnet build && dotnet run",
  nil,
})
eq(
  "run: env from the profile plus the URL",
  runcfg.env({ url = "https://localhost:7001", env = { ASPNETCORE_ENVIRONMENT = "Development" } }),
  {
    ASPNETCORE_ENVIRONMENT = "Development",
    ASPNETCORE_URLS = "https://localhost:7001",
  }
)
runcfg.write("/r", saved)
eq("run: saved configs round-trip through the state file", runcfg.read()["/r"], saved)

-- ── dotnet command builders (no `--project ''` ever) ────────────────────────

local dotnet_cmd = require("utils.csharpdotnet")
eq("dotnet run: project + profile quoted", dotnet_cmd.run_cmd("/r/src/Api/Api.csproj", "https"), "dotnet run --project '/r/src/Api/Api.csproj' --launch-profile 'https'")
eq(
  "dotnet run: no project, no profile → bare command in the cwd",
  { dotnet_cmd.run_cmd("", nil), dotnet_cmd.run_cmd(nil, "") },
  { "dotnet run", "dotnet run" }
)
eq(
  "dotnet watch: same shape as run",
  dotnet_cmd.watch_cmd("/r/Api.csproj", nil),
  "dotnet watch --project '/r/Api.csproj' run"
)
eq("dotnet build: positional path, bare without one", {
  dotnet_cmd.cmd("build", "/r/Api.csproj", {}),
  dotnet_cmd.cmd("build", "", {}),
  dotnet_cmd.cmd("publish", "/r/Api.csproj", { extra = "-c Release" }),
}, {
  "dotnet build '/r/Api.csproj'",
  "dotnet build",
  "dotnet publish '/r/Api.csproj' -c Release",
})

-- ── terminal.run: the command arrives whole (no TermExec truncation) ─────────

package.loaded["toggleterm"] = { exec = function(cmd, num, size, dir, direction)
  _G._captured_term = { cmd, num, size, dir, direction }
end }
package.loaded["toggleterm.terminal"] = { get_all = function()
  return {}
end }
local term = require("utils.terminal")
term.run("dotnet run --project '/a b/Api.csproj' --launch-profile 'https'", "/a b")
local got = _G._captured_term
_G._captured_term = nil
eq("terminal.run: cmd, dir and direction go to the API untouched", {
  got[1],
  got[4],
  got[5] ~= nil,
}, {
  "dotnet run --project '/a b/Api.csproj' --launch-profile 'https'",
  "/a b",
  true,
})

-- ── .http test file from Program.cs ─────────────────────────────────────────

local http = require("utils.csharphttp")
local prog = [[
var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();
app.MapGet("/", () => "hello-world");
app.MapPost("/items", (Item i) => Results.Created());
app.MapGet("/hello/{name}", (string name) => $"hello-{name}");
app.MapGet("/", () => "dup");
]]
eq("http routes: file order, methods, no duplicates", http.routes(prog), {
  { method = "Get", route = "/" },
  { method = "Post", route = "/items" },
  { method = "Get", route = "/hello/{name}" },
})
eq("http sample: {param} becomes world", { http.sample("/hello/{name}"), http.sample("/") }, { "/hello/world", "/" })
eq("http base: first applicationUrl, else the fallback", {
  http.base_url('{"profiles":{"https":{"applicationUrl":"https://localhost:7001;http://localhost:5001"}}}'),
  http.base_url(""),
}, { "https://localhost:7001", "http://localhost:5000" })
local rendered = http.render("http://localhost:5231", http.routes(prog), "HelloApi")
ok(
  "http render: header, one request per route, ### separators",
  rendered:find("### HelloApi (http://localhost:5231)", 1, true) ~= nil
    and rendered:find("GET http://localhost:5231/hello/world", 1, true) ~= nil
    and rendered:find("POST http://localhost:5231/items", 1, true) ~= nil
)
ok("http curl: status line plus the URL", http.curl("http://localhost:5231", { method = "Get", route = "/hello/{name}" }):find("curl", 1, true) == 1
  and http.curl("http://localhost:5231", { method = "Get", route = "/hello/{name}" }):find("http://localhost:5231/hello/world", 1, true) ~= nil)

-- ── .http flow: separate terminal, never overwritten ─────────────────────────

package.loaded["toggleterm.terminal"].Terminal = {
  new = function(_, opts)
    _G._http_term_opts = opts
    return {
      bufnr = 4242,
      is_open = function()
        _G._http_opened = true
        return true
      end,
      open = function()
        _G._http_opened = true
      end,
      send = function(_, cmd)
        _G._http_sent = cmd
      end,
    }
  end,
}
local hdir = base .. "/httpapp"
write(hdir .. "/HelloApi.csproj", "<Project />")
write(hdir .. "/Program.cs", 'var app = builder.Build();\napp.MapGet("/", () => "hi");\n')
write(hdir .. "/Properties/launchSettings.json", '{"profiles":{"http":{"applicationUrl":"http://localhost:5231"}}}')
require("csharp.http").open_for_project(hdir .. "/HelloApi.csproj")
eq("http flow: own terminal (display_name), opened, both curls sent", {
  _G._http_term_opts.display_name,
  _G._http_opened,
  _G._http_sent ~= nil and _G._http_sent:find("http://localhost:5231/", 1, true) ~= nil,
}, { "http test", true, true })
local before = io.open(hdir .. "/requests.http"):read("*a")
_G._http_sent, _G._http_opened = nil, nil
require("csharp.http").open_for_project(hdir .. "/HelloApi.csproj")
eq("http flow: second run reuses and never overwrites", {
  io.open(hdir .. "/requests.http"):read("*a") == before,
  _G._http_sent ~= nil,
}, { true, true })
eq("http flow: controllers-only project warns, sends nothing", (function()
  local cdir = base .. "/ctrapp"
  write(cdir .. "/Api.csproj", "<Project />")
  write(cdir .. "/Program.cs", "var app = builder.Build();\napp.Run();\n")
  _G._http_sent = nil
  require("csharp.http").open_for_project(cdir .. "/Api.csproj")
  return _G._http_sent == nil and vim.uv.fs_stat(cdir .. "/requests.http") == nil
end)(), true)

-- ── Noodle collection from Program.cs ────────────────────────────────────────

local cnoodle = require("utils.csharproodle")
eq("noodle params: {name} and {id:int}, no duplicates", cnoodle.params("/hello/{name}/posts/{id:int}/{name}"), { "name", "id" })
eq("noodle url: {param} becomes :param", cnoodle.noodle_url("/hello/{name}"), "/hello/:name")
eq("noodle slug: / and specials", { cnoodle.slug("/"), cnoodle.slug("/hello/{name}") }, { "root", "hello-name" })
eq("noodle filename", { cnoodle.filename("Get", "/"), cnoodle.filename("Post", "/items") }, { "get-root.yml", "post-items.yml" })
local nyml = cnoodle.request_yml("Get", "/hello/{name}", "/hello/world")
ok(
  "noodle request: name/method/url, native :param, sample, assert 200, smoke tag",
  nyml:find("name: GET /hello/world", 1, true) ~= nil
    and nyml:find("method: GET", 1, true) ~= nil
    and nyml:find("url: $base_url/hello/:name", 1, true) ~= nil
    and nyml:find("- name: name\n    value: world", 1, true) ~= nil
    and nyml:find("operator: equals\n    value: 200", 1, true) ~= nil
    and nyml:find("- smoke", 1, true) ~= nil
)
local pyml = cnoodle.request_yml("Post", "/items", "/items")
ok(
  "noodle request: POST carries an empty JSON body, no assert",
  pyml:find("body_type: json", 1, true) ~= nil and pyml:find("assert:", 1, true) == nil
)
eq("noodle settings + env", {
  cnoodle.settings_yml("HelloApi"),
  cnoodle.env_file("http://localhost:5231"),
}, {
  "name: HelloApi\nenvironment: local\n",
  "_color=info\nbase_url=http://localhost:5231\n",
})

-- ── Noodle flow: files created, TUI in its own terminal ──────────────────────

local ndir = base .. "/noodleapp"
write(ndir .. "/HelloApi.csproj", "<Project />")
write(ndir .. "/Program.cs", 'var app = builder.Build();\napp.MapGet("/", () => "hi");\napp.MapGet("/hello/{name}", (string n) => n);\n')
write(ndir .. "/Properties/launchSettings.json", '{"profiles":{"http":{"applicationUrl":"http://localhost:5231"}}}')
local nomod = require("csharp.noodle")
nomod.has_noodle = function()
  return true
end
_G._http_sent, _G._http_term_opts = nil, nil
nomod.open_collection(ndir .. "/HelloApi.csproj")
local ncol = ndir .. "/noodle"
local function nread(f)
  return io.open(ncol .. "/" .. f):read("*a")
end
eq("noodle flow: TUI opens with --collection + --env in the `noodle` terminal", {
  _G._http_term_opts.display_name,
  _G._http_sent ~= nil and _G._http_sent:find("noodle --collection", 1, true) ~= nil,
  _G._http_sent ~= nil and _G._http_sent:find("--env local", 1, true) ~= nil,
}, { "noodle", true, true })
eq("noodle flow: settings, env and one file per route", {
  nread("settings.yml"),
  nread(".environments/local.env"),
  nread("get-root.yml"):find("url: $base_url/", 1, true) ~= nil,
  nread("get-hello-name.yml"):find("url: $base_url/hello/:name", 1, true) ~= nil,
}, {
  "name: HelloApi\nenvironment: local\n",
  "_color=info\nbase_url=http://localhost:5231\n",
  true,
  true,
})
local nbefore = nread("get-root.yml")
_G._http_sent = nil
nomod.open_collection(ndir .. "/HelloApi.csproj")
eq("noodle flow: second run never overwrites, still opens TUI", {
  nread("get-root.yml") == nbefore,
  _G._http_sent ~= nil,
}, { true, true })
nomod.has_noodle = function()
  return false
end
_G._http_sent = nil
local nondir = base .. "/noodlenobin"
write(nondir .. "/Api.csproj", "<Project />")
write(nondir .. "/Program.cs", 'var a = builder.Build();\na.MapGet("/", () => "x");\n')
nomod.open_collection(nondir .. "/Api.csproj")
eq("noodle flow: without the binary it still writes files but opens nothing", {
  vim.uv.fs_stat(nondir .. "/noodle/get-root.yml") ~= nil,
  _G._http_sent,
}, { true, nil })

-- ── NuGet Manager ───────────────────────────────────────────────────────────

-- `dotnet list package --format json` with direct + transitive, one outdated, one vulnerable
local list_all = proj.parse_list_all([[
{"version":1,"projects":[{"path":"/r/src/Api/Api.csproj","frameworks":[{"framework":"net10.0",
  "topLevelPackages":[{"id":"Serilog.AspNetCore","requestedVersion":"9.0.0","resolvedVersion":"9.0.0"}],
  "transitivePackages":[{"id":"Serilog","resolvedVersion":"4.0.0"}]}]}]}
]])
eq("nuget: list all splits direct and transitive", {
  { list_all[1].id, list_all[1].direct },
  { list_all[2].id, list_all[2].direct },
  #list_all,
}, { { "Serilog.AspNetCore", true }, { "Serilog", false }, 2 })
eq("nuget: assets graph gives the edges, `<root>` kept apart", {
  proj.parse_assets([[{"targets":{"net10.0":{"Serilog.AspNetCore/9.0.0":{"dependencies":{"Serilog":"4.0.0"}}}}}]])["Serilog.AspNetCore"],
  proj.parse_assets([[{"project":{"dependencies":{"net10.0":{"Serilog.AspNetCore":"9.0.0"}}}}]])["<root>"],
  proj.parse_assets("not json"),
}, { { "Serilog" }, { "Serilog.AspNetCore" }, {} })
local nuget = require("utils.csharpnuget")
local nrows = nuget.rows(
  list_all,
  outdated,
  vulnerable,
  nuget.graph(
    proj.parse_assets([[{"targets":{"net10.0":{"Serilog.AspNetCore/9.0.0":{"dependencies":{"Serilog":"4.0.0"}}}}}]]),
    list_all
  )
)
eq("nuget: rows group direct and transitive, vulnerable on top", {
  nrows[3].group,
  nrows[6].group,
  #vim.tbl_filter(function(r)
    return r.pkg and r.pkg.id == "Serilog"
  end, nrows),
}, { "Direct", "Transitive", 1 })
ok(
  "nuget: detail names the version and the graph child",
  table
    .concat(nuget.detail({ pkg = list_all[1], children = { "Serilog" } }, list_all), "\n")
    :find("SERILOG.ASPNETCORE", 1, true)
      ~= nil
    and table
        .concat(nuget.detail({ pkg = list_all[1], children = { "Serilog" } }, list_all), "\n")
        :find("→ Serilog", 1, true)
      ~= nil
)

vim.fn.delete(base, "rf")
print(("%d/%d passed"):format(total - fails, total))
if fails == 0 then
  print("ALL OK")
else
  print(("FAILURES: %d"):format(fails))
end
vim.cmd("qa!")
