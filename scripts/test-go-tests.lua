-- Tests for the shared `go test` line (utils/gotest.lua): every test action of <leader>g is verbose by default,
-- settings.go.test is read when the command is built (so the settings panel applies to the next run), and extra
-- flags land BEFORE the package: `go test -v -race ./...`, never `./... -race`.
local fails = 0
local function print(...)
  io.stdout:write(table.concat(vim.tbl_map(tostring, { ... }), "\t"), "\n")
end
local function eq(name, got, want)
  if vim.deep_equal(got, want) then
    print("ok   " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. "\n  got:  " .. vim.inspect(got) .. "\n  want: " .. vim.inspect(want))
  end
end
local function ok(name, cond)
  eq(name, cond and true or false, true)
end

local settings = require "core.settings"
local gotest = require "utils.gotest"

-- the scope is shell-quoted (folders with spaces must survive); the flags never are
local function q(scope)
  return vim.fn.shellescape(scope)
end

local original = vim.deepcopy(settings.go.test)

settings.go.test = { verbose = true }
eq("default: the file's package is verbose", gotest.command(nil, "./cmd/api"), "go test -v " .. q "./cmd/api")
eq("default: the whole module is verbose", gotest.command(nil, "./..."), "go test -v " .. q "./...")
eq("action flags go before the scope", gotest.command({ "-race" }, "./..."), "go test -v -race " .. q "./...")
eq(
  "several action flags keep their order",
  gotest.command({ "-cover", "-timeout=5m" }, "./..."),
  "go test -v -cover -timeout=5m " .. q "./..."
)

settings.go.test = { verbose = false }
eq("verbose off: short form", gotest.command({ "-race" }, "./..."), "go test -race " .. q "./...")

settings.go.test = { verbose = true, args = { "-count=1", "-tags=integration" } }
eq(
  "settings args ride along after the action flags",
  gotest.command({ "-cover" }, "./..."),
  "go test -v -cover -count=1 -tags=integration " .. q "./..."
)

-- a settings table without the key (local.lua replaced it) still defaults to verbose
settings.go.test = {}
eq("missing verbose means verbose", gotest.command(nil, "."), "go test -v " .. q ".")

-- a folder with a space still reaches the shell as one argument
eq("scopes are quoted", gotest.command(nil, "./cmd/my api"), "go test -v './cmd/my api'")

-- langtest's mode: one event per test, no -v
settings.go.test = { verbose = true }
eq("json mode asks go test for json, not -v", gotest.args(nil, "./...", { json = true }), {
  "go",
  "test",
  "-json",
  "./...",
})
settings.go.test = { verbose = true, args = { "-count=1" } }
eq("json mode keeps settings args before the scope", gotest.args({ "-race" }, "./...", { json = true }), {
  "go",
  "test",
  "-json",
  "-race",
  "-count=1",
  "./...",
})

-- ── the Go adapter (langtest) ────────────────────────────────────────────────

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/pkg", "p")
local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end
write(root .. "/go.mod", "module example.com/probe\n\ngo 1.21\n")
local test_file = root .. "/pkg/calc_test.go"
write(
  test_file,
  table.concat({
    "package pkg",
    "",
    'import "testing"',
    "",
    "func TestMain(m *testing.M) {}",
    "",
    "func TestAdd(t *testing.T) {",
    "\tif true {",
    '\t\tt.Fatalf("got 2")',
    "\t}",
    "}",
    "",
    "func TestSub(t *testing.T) {",
    '\tt.Run("one", func(t *testing.T) {',
    '\t\tt.Fatal("sub failed")',
    "\t})",
    "}",
    "",
    "func BenchmarkAdd(b *testing.B) {}",
    "",
    "func helper() {}",
    "",
    "func TestOK(t *testing.T) {}",
    "",
  }, "\n")
)
local go = require "langtest.adapters.go"
eq("go root: the module", go.root(test_file), root)
eq("go is_test", { go.is_test(test_file), go.is_test(root .. "/pkg/calc.go") }, { true, false })
eq("go alternate: source and test", {
  go.alternate(root .. "/pkg/calc.go"),
  go.alternate(test_file),
}, { test_file, root .. "/pkg/calc.go" })
eq("go module", go.module "module example.com/probe\n", "example.com/probe")
eq("go package dir", go.package_dir(root, "example.com/probe/pkg [example.com/probe/pkg.test]", "example.com/probe"), root .. "/pkg")

local function has_parser(lang)
  local ok, added = pcall(vim.treesitter.language.add, lang)
  return ok and added ~= false
end
if has_parser "go" then
  local buf = vim.fn.bufadd(test_file)
  vim.fn.bufload(buf)
  vim.bo[buf].filetype = "go"
  eq(
    "go tests: Test functions, not TestMain, benchmarks or helpers",
    vim.tbl_map(function(d)
      return { d.id, d.line }
    end, go.tests(buf)),
    { { "TestAdd", 7 }, { "TestSub", 13 }, { "TestOK", 23 } }
  )
  vim.cmd "bwipeout!"
else
  print "skip: no go parser"
end

local go_json = table.concat({
  '{"Action":"start","Package":"example.com/probe/pkg"}',
  '{"Action":"run","Package":"example.com/probe/pkg","Test":"TestOK"}',
  '{"Action":"output","Package":"example.com/probe/pkg","Test":"TestOK","Output":"=== RUN   TestOK\\n"}',
  '{"Action":"output","Package":"example.com/probe/pkg","Test":"TestOK","Output":"--- PASS: TestOK (0.00s)\\n"}',
  '{"Action":"pass","Package":"example.com/probe/pkg","Test":"TestOK","Elapsed":0}',
  '{"Action":"run","Package":"example.com/probe/pkg","Test":"TestAdd"}',
  '{"Action":"output","Package":"example.com/probe/pkg","Test":"TestAdd","Output":"    calc_test.go:7: got 2\\n"}',
  '{"Action":"fail","Package":"example.com/probe/pkg","Test":"TestAdd","Elapsed":0}',
  '{"Action":"run","Package":"example.com/probe/pkg","Test":"TestSub"}',
  '{"Action":"run","Package":"example.com/probe/pkg","Test":"TestSub/one"}',
  '{"Action":"output","Package":"example.com/probe/pkg","Test":"TestSub/one","Output":"    calc_test.go:12: sub failed\\n"}',
  '{"Action":"fail","Package":"example.com/probe/pkg","Test":"TestSub/one"}',
  '{"Action":"fail","Package":"example.com/probe/pkg","Test":"TestSub"}',
  '{"Action":"fail","Package":"example.com/probe/pkg"}',
}, "\n")
local ctx = { root = root, file = test_file, rel = "pkg/calc_test.go", scope = "all" }
local results = go.parse({ stdout = go_json, stderr = "" }, ctx)
local by = {}
for _, r in ipairs(results) do
  by[r.id] = r
end
eq("go parse: one result per top-level test, subtests folded into the parent", vim.tbl_map(function(r)
  return { r.id, r.status }
end, results), { { "TestOK", "pass" }, { "TestAdd", "fail" }, { "TestSub", "fail" } })
eq("go parse: the failure's file, line and message", {
  by.TestAdd and by.TestAdd.file,
  by.TestAdd and by.TestAdd.fail_line,
  by.TestAdd and by.TestAdd.message,
}, { test_file, 7, "got 2" })
eq("go parse: a failing subtest reports on its parent", {
  by.TestSub and by.TestSub.message,
  by.TestSub and by.TestSub.fail_line,
}, { "sub failed", 12 })
eq("go parse: a test that passed still finds its file", by.TestOK and by.TestOK.file, test_file)
ok(
  "go display: the human output, not the JSON stream",
  table.concat(go.display { stdout = go_json, stderr = "" }, "\n"):find("got 2", 1, true) ~= nil
)

local build_json = table.concat({
  '{"ImportPath":"example.com/probe/pkg [example.com/probe/pkg.test]","Action":"build-output","Output":"# example.com/probe/pkg [example.com/probe/pkg.test]\\n"}',
  '{"ImportPath":"example.com/probe/pkg [example.com/probe/pkg.test]","Action":"build-output","Output":"./calc_test.go:6:18: undefined: undefinedThing\\n"}',
  '{"ImportPath":"example.com/probe/pkg [example.com/probe/pkg.test]","Action":"build-fail"}',
  '{"Action":"start","Package":"example.com/probe/pkg"}',
  '{"Action":"output","Package":"example.com/probe/pkg","Output":"FAIL\\texample.com/probe/pkg [build failed]\\n"}',
  '{"Action":"fail","Package":"example.com/probe/pkg","Elapsed":0,"FailedBuild":"example.com/probe/pkg [example.com/probe/pkg.test]"}',
}, "\n")
local broken = go.parse({ stdout = build_json, stderr = "" }, ctx)
eq("go parse: a broken _test.go is one build failure, with its line", {
  #broken,
  broken[1] and broken[1].status,
  broken[1] and broken[1].build,
  broken[1] and broken[1].file,
  broken[1] and broken[1].fail_line,
}, { 1, "fail", true, test_file, 6 })
ok("go parse: its message names the compile error", broken[1].message:find("undefinedThing", 1, true) ~= nil)

settings.go.test = { verbose = true }
eq("go command nearest: json, the package folder, the anchored test", go.command {
  scope = "nearest",
  root = root,
  file = test_file,
  test = { id = "TestAdd" },
}, { "go", "test", "-json", "-run", "^TestAdd$", "./pkg" })
eq(
  "go command file: the file's folder from the module root",
  go.command { scope = "file", root = root, file = test_file },
  { "go", "test", "-json", "./pkg" }
)
write(root .. "/calc_test.go", "package probe\n")
eq(
  "go command file: the module root package is .",
  go.command { scope = "file", root = root, file = root .. "/calc_test.go" },
  { "go", "test", "-json", "." }
)
eq("go command all: ./... and the action's flags", go.command {
  scope = "all",
  root = root,
  file = test_file,
  flags = { "-race" },
}, { "go", "test", "-json", "-race", "./..." })

vim.fn.delete(root, "rf")

settings.go.test = original
print(fails == 0 and "\nALL OK" or ("\nFAILURES: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
