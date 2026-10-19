-- Tests of the language packs (Python, TypeScript/JavaScript, Rust, SQL, Swift, Make): the registry (packs, every
-- language reachable, formatter options), tests in the editor (langtest: each adapter's tests from a real buffer with
-- treesitter, its command, its report parsed from real runner output), the SQL runner's pure parts (statements, risky
-- ones, connections), the project setup presets (every one parses, fills every placeholder, valid JSON), and the small
-- pure helpers of the menus (tsc errors, cargo executables). Hermetic: no runner, database or network.
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "luafile scripts/test-langs.lua"
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

--- A buffer of a file with that text and filetype (treesitter parses it)
local function buffer(path, text, ft)
  write(path, text)
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  vim.bo[buf].filetype = ft
  return buf
end

local function has_parser(lang)
  return pcall(vim.treesitter.language.add, lang) and select(2, pcall(vim.treesitter.language.add, lang)) ~= false
end

-- ── the registry and the packs ───────────────────────────────────────────────

local packs = require "languages.packs"
local names = {}
for line in io.lines(root .. "/nvim/lua/languages/init.lua") do
  local n = line:match '^%s+"([%w_]+)",$'
  if n then
    names[#names + 1] = n
  end
end
local covered = {}
for _, n in ipairs(packs.base) do
  covered[n] = true
end
for _, p in ipairs(packs.packs) do
  ok("pack " .. p.id .. ": one line in packs.lua (the installer reads it with sed)", true)
  for _, n in ipairs(p.langs) do
    covered[n] = true
    ok("pack " .. p.id .. ": " .. n .. " is a registry language", vim.tbl_contains(names, n))
  end
end
eq(
  "packs: every registry language is reachable",
  vim.tbl_filter(function(n)
    return not covered[n]
  end, names),
  {}
)
local one_line = 0
for line in io.lines(root .. "/nvim/lua/languages/packs.lua") do
  if line:match '^%s+{ id = "[%w_]+", label = "[^"]+", langs = {[^}]*}, detect = {[^}]*} },$' then
    one_line = one_line + 1
  end
end
eq("packs: each on a line of its own, in the shape install.sh parses", one_line, #packs.packs)
for _, lang in ipairs { "python", "rust", "typescript", "sql", "swift", "make" } do
  local spec = dofile(root .. "/nvim/lua/languages/" .. lang .. ".lua")
  ok(lang .. ": declares its parsers", type(spec.treesitter) == "table" and #spec.treesitter > 0)
end
local ts_spec = dofile(root .. "/nvim/lua/languages/typescript.lua")
eq("typescript: biome only where the project has a biome.json, prettier otherwise", {
  ts_spec.formatters.typescript[1],
  ts_spec.formatters.typescript[2],
  ts_spec.formatters.typescript.stop_after_first,
  ts_spec.formatter_options.biome.require_cwd,
}, { "biome", "prettier", true, true })
local py_spec = dofile(root .. "/nvim/lua/languages/python.lua")
eq("python: ruff in light mode too (always), the servers otherwise", {
  vim.tbl_contains(py_spec.mason.always, "ruff"),
  vim.tbl_contains(py_spec.lsp, "basedpyright"),
  py_spec.linters_light.python[1],
}, { true, true, "ruff" })

-- ── langtest: JUnit ──────────────────────────────────────────────────────────

local junit = require "langtest.junit"
local xml =
  [[<?xml version="1.0" encoding="utf-8"?><testsuites><testsuite name="pytest" errors="0" failures="1" skipped="1" tests="3">
<testcase classname="tests.test_calc.TestCalc" name="test_add" file="tests/test_calc.py" line="4" time="0.001" />
<testcase classname="tests.test_calc" name="test_div[0-1]" file="tests/test_calc.py" line="9" time="0.001"><failure message="ZeroDivisionError: division by zero">def test_div(a, b):
&gt;       assert a / b
E       ZeroDivisionError: division by zero

tests/test_calc.py:11: ZeroDivisionError</failure></testcase>
<testcase classname="tests.test_calc" name="test_skip" file="tests/test_calc.py" line="13" time="0"><skipped type="pytest.skip" message="later">skipped</skipped></testcase>
</testsuite></testsuites>]]
local cases = junit.cases(xml)
eq(
  "junit: every case with its status",
  vim.tbl_map(function(c)
    return { c.name, c.status, c.line }
  end, cases),
  { { "test_add", "pass", 4 }, { "test_div[0-1]", "fail", 9 }, { "test_skip", "skip", 13 } }
)
ok(
  "junit: the failure's message and body, entities decoded",
  cases[2].message == "ZeroDivisionError: division by zero" and cases[2].text:find("> ", 1, true)
)

-- ── pytest ───────────────────────────────────────────────────────────────────

local pytest = require "langtest.adapters.pytest"
local proot = base .. "/py"
write(proot .. "/pyproject.toml", '[project]\nname = "calc"\nrequires-python = ">=3.13"\n')
local pybuf = buffer(
  proot .. "/tests/test_calc.py",
  table.concat({
    "import pytest",
    "",
    "class TestCalc:",
    "    def test_add(self):",
    "        assert 1 + 1 == 2",
    "",
    "    def helper(self):",
    "        pass",
    "",
    "@pytest.mark.parametrize('a,b', [(0, 1)])",
    "def test_div(a, b):",
    "    assert a / b",
    "",
    "class Other:",
    "    def test_not_collected(self):",
    "        pass",
  }, "\n"),
  "python"
)
if has_parser "python" then
  local defs = pytest.tests(pybuf)
  eq(
    "pytest tests: Test classes, test functions (decorated too), not helpers nor other classes",
    vim.tbl_map(function(d)
      return { d.id, d.kind, d.line }
    end, defs),
    { { "TestCalc", "group", 3 }, { "TestCalc::test_add", "test", 4 }, { "test_div", "test", 10 } }
  )
  eq("nearest: the method under the cursor", require("langtest.ts").nearest(defs, 5).id, "TestCalc::test_add")
  eq("nearest: on the decorator line, its function", require("langtest.ts").nearest(defs, 10).id, "test_div")
else
  print "skip: no python parser"
end
eq("pytest root: the project", pytest.root(proot .. "/tests/test_calc.py"), proot)
eq(
  "pytest is_test",
  { pytest.is_test "tests/test_calc.py", pytest.is_test "calc_test.py", pytest.is_test "calc.py" },
  { true, true, false }
)
local ctx = {
  scope = "nearest",
  root = proot,
  file = proot .. "/tests/test_calc.py",
  rel = "tests/test_calc.py",
  test = { id = "TestCalc::test_add", kind = "test" },
  report = "/tmp/r.xml",
}
local cmd = pytest.command(ctx)
ok(
  "pytest command: the node id, the junit report",
  vim.tbl_contains(cmd, "tests/test_calc.py::TestCalc::test_add")
    and vim.tbl_contains(cmd, "--junitxml=/tmp/r.xml")
    and vim.tbl_contains(cmd, "junit_family=xunit1")
)
local presults = pytest.parse({ report = xml }, ctx)
eq(
  "pytest parse: ids the buffer's tests have (parametrized folded into its function)",
  vim.tbl_map(function(r)
    return { r.id, r.status }
  end, presults),
  { { "TestCalc::test_add", "pass" }, { "test_div", "fail" }, { "test_skip", "skip" } }
)
eq("pytest parse: the line of the test file the failure stops at", presults[2].fail_line, 11)
eq("pytest parse: 0-based lines made 1-based", presults[1].line, 5)
eq(
  "pytest alternate: a module's test under tests/",
  pytest.alternate(proot .. "/calc/ops.py", proot),
  proot .. "/tests/test_ops.py"
)

-- ── vitest / jest / bun ──────────────────────────────────────────────────────

local js = require "langtest.adapters.jsunit"
local jroot = base .. "/js"
write(jroot .. "/package.json", '{"name":"web","devDependencies":{"vitest":"^3"}}')
eq("js runner: vitest from the dependencies", js.runner(jroot), "vitest")
write(base .. "/jest/package.json", '{"scripts":{"test":"jest"}}')
eq("js runner: jest from the test script", js.runner(base .. "/jest"), "jest")
write(base .. "/bunp/package.json", "{}")
write(base .. "/bunp/bun.lock", "")
eq("js runner: bun in a bun project with neither", js.runner(base .. "/bunp"), "bun")
write(base .. "/none/package.json", "{}")
eq("js runner: none", js.runner(base .. "/none"), nil)
local jsbuf = buffer(
  jroot .. "/src/sum.test.ts",
  table.concat({
    'import { describe, it, expect } from "vitest";',
    'describe("sum", () => {',
    '  it("adds", () => {',
    "    expect(1 + 1).toBe(2);",
    "  });",
    '  it.skip("later", () => {});',
    '  describe.each([1])("with %i", () => {',
    '    test("works", () => {});',
    "  });",
    "});",
  }, "\n"),
  "typescript"
)
if has_parser "typescript" then
  eq(
    "js tests: describe/it/test, .skip and .each, nested ids",
    vim.tbl_map(function(d)
      return { d.id, d.kind, d.line }
    end, js.tests(jsbuf)),
    {
      { "sum", "group", 2 },
      { "sum > adds", "test", 3 },
      { "sum > later", "test", 6 },
      { "sum > with %i", "group", 7 },
      { "sum > with %i > works", "test", 8 },
    }
  )
else
  print "skip: no typescript parser"
end
local jctx = {
  scope = "nearest",
  root = jroot,
  file = jroot .. "/src/sum.test.ts",
  rel = "src/sum.test.ts",
  test = { id = "sum > adds", kind = "test" },
  report = "/tmp/r.json",
}
local jcmd = js.command(jctx)
ok(
  "vitest command: run, the json reporter, the file, the full name as an anchored pattern",
  vim.tbl_contains(jcmd, "vitest")
    and vim.tbl_contains(jcmd, "run")
    and vim.tbl_contains(jcmd, "--reporter=json")
    and vim.tbl_contains(jcmd, "src/sum.test.ts")
    and vim.tbl_contains(jcmd, "^sum adds$")
)
ok("vitest command: never a download (npx --no-install)", jcmd[1] == "npx" and jcmd[2] == "--no-install")
local report = vim.json.encode {
  testResults = {
    {
      name = jroot .. "/src/sum.test.ts",
      assertionResults = {
        {
          ancestorTitles = { "sum" },
          title = "adds",
          fullName = "sum adds",
          status = "passed",
          location = { line = 3, column = 3 },
          failureMessages = {},
        },
        {
          ancestorTitles = { "sum" },
          title = "subtracts",
          status = "failed",
          failureMessages = { "AssertionError: expected 1 to be 2\n    at " .. jroot .. "/src/sum.test.ts:9:19" },
        },
        { ancestorTitles = { "sum" }, title = "later", status = "skipped", failureMessages = {} },
      },
    },
  },
}
local jres = js.parse({ report = report }, jctx)
eq(
  "vitest parse: ids, statuses",
  vim.tbl_map(function(r)
    return { r.id, r.status }
  end, jres),
  { { "sum > adds", "pass" }, { "sum > subtracts", "fail" }, { "sum > later", "skip" } }
)
eq(
  "vitest parse: the message and the line in the test file",
  { jres[2].message, jres[2].fail_line },
  { "AssertionError: expected 1 to be 2", 9 }
)
eq(
  "js alternate: next to it, and back",
  { js.alternate "/p/src/sum.ts", js.alternate "/p/src/sum.test.ts" },
  { "/p/src/sum.test.ts", "/p/src/sum.ts" }
)

-- ── cargo ────────────────────────────────────────────────────────────────────

local cargo = require "langtest.adapters.cargo"
eq(
  "cargo module of a file",
  vim.tbl_map(cargo.module_of, { "src/lib.rs", "src/calc.rs", "src/net/mod.rs", "src/net/http.rs", "tests/api.rs" }),
  { "", "calc", "net", "net::http", nil }
)
local rroot = base .. "/rs"
write(rroot .. "/Cargo.toml", '[package]\nname = "calc"\nedition = "2024"\n')
local rbuf = buffer(
  rroot .. "/src/calc.rs",
  table.concat({
    "pub fn add(a: i32, b: i32) -> i32 { a + b }",
    "",
    "#[cfg(test)]",
    "mod tests {",
    "    use super::*;",
    "",
    "    #[test]",
    "    fn adds() {",
    "        assert_eq!(add(1, 1), 2);",
    "    }",
    "",
    "    #[tokio::test]",
    "    async fn async_adds() {}",
    "",
    "    fn helper() {}",
    "}",
  }, "\n"),
  "rust"
)
if has_parser "rust" then
  eq(
    "cargo tests: the mod, #[test] and #[tokio::test], not helpers, with the file's module",
    vim.tbl_map(function(d)
      return { d.id, d.kind, d.line }
    end, cargo.tests(rbuf)),
    { { "calc::tests", "group", 4 }, { "calc::tests::adds", "test", 7 }, { "calc::tests::async_adds", "test", 12 } }
  )
else
  print "skip: no rust parser"
end
local rctx = {
  scope = "nearest",
  root = rroot,
  file = rroot .. "/src/calc.rs",
  rel = "src/calc.rs",
  test = { id = "calc::tests::adds", kind = "test" },
}
eq(
  "cargo command nearest: the path, --exact",
  cargo.command(rctx),
  { "cargo", "test", "calc::tests::adds", "--", "--exact" }
)
eq(
  "cargo command file: the module's prefix",
  cargo.command(vim.tbl_extend("force", rctx, { scope = "file" })),
  { "cargo", "test", "calc::" }
)
eq(
  "cargo command integration file: its target",
  cargo.command { scope = "file", rel = "tests/api.rs" },
  { "cargo", "test", "--test", "api" }
)
local cargo_out = table.concat({
  "running 3 tests",
  "test calc::tests::adds ... ok",
  "test calc::tests::subtracts ... FAILED",
  "test calc::tests::later ... ignored",
  "",
  "failures:",
  "",
  "---- calc::tests::subtracts stdout ----",
  "",
  "thread 'calc::tests::subtracts' panicked at src/calc.rs:14:9:",
  "assertion `left == right` failed",
  "  left: 0",
  " right: 1",
  "",
  "failures:",
  "    calc::tests::subtracts",
  "",
  "test result: FAILED. 1 passed; 1 failed; 1 ignored",
}, "\n")
local rres = cargo.parse({ stdout = cargo_out, stderr = "" }, rctx)
eq(
  "cargo parse: every test line",
  vim.tbl_map(function(r)
    return { r.id, r.status }
  end, rres),
  { { "calc::tests::adds", "pass" }, { "calc::tests::subtracts", "fail" }, { "calc::tests::later", "skip" } }
)
eq(
  "cargo parse: where it panicked and why",
  { rres[2].file, rres[2].fail_line, rres[2].message },
  { rroot .. "/src/calc.rs", 14, "assertion `left == right` failed" }
)

-- ── swift ────────────────────────────────────────────────────────────────────

local swift = require "langtest.adapters.swift"
local sroot = base .. "/sw"
write(
  sroot .. "/Package.swift",
  '// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: "Calc")\n'
)
local sbuf = buffer(
  sroot .. "/Tests/CalcTests/CalcTests.swift",
  table.concat({
    "import XCTest",
    "@testable import Calc",
    "",
    "final class CalcTests: XCTestCase {",
    "    func testAdd() {",
    "        XCTAssertEqual(1 + 1, 2)",
    "    }",
    "    func helper() {}",
    "}",
    "",
    "import Testing",
    "@Test func adds() {",
    "    #expect(1 + 1 == 2)",
    "}",
  }, "\n"),
  "swift"
)
if has_parser "swift" then
  eq(
    "swift tests: an XCTestCase and its test methods, a @Test function",
    vim.tbl_map(function(d)
      return { d.id, d.kind, d.line, d.filter }
    end, swift.tests(sbuf)),
    {
      { "CalcTests", "group", 4, "CalcTests" },
      { "CalcTests.testAdd", "test", 5, "CalcTests/testAdd" },
      { "adds", "test", 12, "adds" },
    }
  )
else
  print "skip: no swift parser"
end
eq(
  "swift command nearest: its filter",
  swift.command { scope = "nearest", test = { id = "CalcTests.testAdd", filter = "CalcTests/testAdd" } },
  { "swift", "test", "--filter", "CalcTests/testAdd" }
)
local swift_out = table.concat({
  "Test Suite 'All tests' started",
  "Test Case 'CalcTests.testAdd' started",
  "Test Case 'CalcTests.testAdd' passed (0.001 seconds)",
  sroot
    .. '/Tests/CalcTests/CalcTests.swift:9: error: CalcTests.testSub : XCTAssertEqual failed: ("0") is not equal to ("1")',
  "Test Case 'CalcTests.testSub' failed (0.002 seconds)",
  "􀟈 Test adds() started.",
  "✔ Test adds() passed after 0.001 seconds.",
  "✘ Test halves() recorded an issue at CalcTests.swift:20:5: Expectation failed: 1 == 2",
  "✘ Test halves() failed after 0.002 seconds with 1 issue.",
}, "\n")
local sres = swift.parse({ stdout = swift_out, stderr = "" }, { root = sroot })
local by = {}
for _, r in ipairs(sres) do
  by[r.id] = r
end
eq("swift parse: XCTest and Swift Testing results", {
  by["CalcTests.testAdd"] and by["CalcTests.testAdd"].status,
  by["CalcTests.testSub"] and by["CalcTests.testSub"].status,
  by["adds"] and by["adds"].status,
  by["halves"] and by["halves"].status,
}, { "pass", "fail", "pass", "fail" })
eq(
  "swift parse: the failure's line and message",
  { by["CalcTests.testSub"].fail_line, by["halves"].fail_line, by["halves"].message },
  { 9, 20, "Expectation failed: 1 == 2" }
)
eq(
  "swift alternate",
  swift.alternate(sroot .. "/Sources/Calc/Parser.swift", sroot),
  sroot .. "/Tests/CalcTests/ParserTests.swift"
)

-- ── langtest core ────────────────────────────────────────────────────────────

local langtest = require "langtest"
eq(
  "summary: the totals",
  (langtest.summary({ { status = "pass" }, { status = "fail" }, { status = "skip" }, { status = "pass" } }, 1.25)),
  "Tests: 2 passed, 1 failed, 1 skipped · 1.2s"
)
eq("match: a result by id, else by a unique name", {
  langtest.match({ ["a::b"] = { name = "b" } }, { id = "a::b", name = "b" }) ~= nil,
  langtest.match({ ["x::adds"] = { name = "adds" } }, { id = "y::adds", name = "adds" }) ~= nil,
  langtest.match(
    { ["x::adds"] = { name = "adds" }, ["z::adds"] = { name = "adds" } },
    { id = "y::adds", name = "adds" }
  ),
}, { true, true, nil })
eq(
  "maps: the same keys in every menu",
  vim.tbl_map(function(m)
    return m[1]
  end, langtest.maps()),
  { "m", "M", "A", ".", "T", "O" }
)

-- ── SQL ──────────────────────────────────────────────────────────────────────

local st = require "sqlrun.statement"
local sql_lines = {
  "-- users first",
  "select * from users where name = 'a;b';",
  "",
  "create function f() returns int as $$",
  "  select 1; -- inside the body",
  "$$ language sql;",
  "/* a ; comment */ delete from users",
  "  where id = 1;",
  "update users set name = 'x'",
}
local stmts = st.split(sql_lines)
eq(
  "split: semicolons in strings, dollar bodies and comments do not end a statement",
  vim.tbl_map(function(s)
    return { s.first, s.last }
  end, stmts),
  { { 2, 2 }, { 4, 6 }, { 7, 8 }, { 9, 9 } }
)
eq("at: the statement under the cursor", st.at(sql_lines, 5).first, 4)
eq("at: on a blank line, the one before", st.at(sql_lines, 3).first, 2)
eq("risky: what changes or drops with no limit", {
  st.risky "delete from users",
  st.risky "delete from users where id = 1",
  st.risky "update users set a = 1",
  st.risky "UPDATE users SET a = 1 WHERE id = 2",
  st.risky "drop table users",
  st.risky "truncate users",
  st.risky "select * from users",
  st.risky "-- where\ndelete from users",
}, {
  "a DELETE with no WHERE removes every row",
  nil,
  "an UPDATE with no WHERE changes every row",
  nil,
  "it drops a table or schema",
  "it empties a table",
  nil,
  "a DELETE with no WHERE removes every row",
})
eq("reads: only reads run under EXPLAIN ANALYZE without a question", {
  st.reads "select 1",
  st.reads "with a as (select 1) select * from a",
  st.reads "with a as (delete from t returning *) select * from a",
  st.reads "insert into t values (1)",
}, { true, true, false, false })
local conn = require "sqlrun.connections"
eq(
  "env: export, quotes, comments",
  conn.parse_env "export DATABASE_URL=\"postgres://u:p@h/db\"\n# x\nOTHER=1 # note\nQUOTED='a b'\n",
  { DATABASE_URL = "postgres://u:p@h/db", OTHER = "1", QUOTED = "a b" }
)
eq("kind: postgres URLs, sqlite URLs and files", {
  { conn.kind "postgresql://h/db" },
  { conn.kind "sqlite:///data/app.db" },
  { conn.kind "data/app.sqlite3" },
  { conn.kind "mysql://h/db" },
}, { { "postgres", "postgresql://h/db" }, { "sqlite", "data/app.db" }, { "sqlite", "data/app.sqlite3" }, {} })
local list = conn.list {
  settings = { { name = "prod", url = "postgres://ro@prod/app" } },
  env_files = {
    [".env"] = "DATABASE_URL=postgres://app@localhost/app\nTEST_DATABASE_URL=postgres://app@localhost/test\n",
  },
  env_url = "postgres://app@localhost/app",
  sqlite = { base .. "/app/data/app.db" },
  root = base .. "/app",
}
eq(
  "list: settings first, the .env URLs (DATABASE_URL first), the environment (not twice), the SQLite files",
  vim.tbl_map(function(c)
    return { c.name, c.kind }
  end, list),
  {
    { "prod", "postgres" },
    { "DATABASE_URL (.env)", "postgres" },
    { "TEST_DATABASE_URL (.env)", "postgres" },
    { "data/app.db", "sqlite" },
  }
)
eq(
  "shown: no password on screen",
  conn.shown "postgres://app:s3cret@localhost/app",
  "postgres://app:•••@localhost/app"
)
local sqlrun = require "sqlrun"
eq(
  "command: psql never prompts and stops at the first error",
  sqlrun.command { kind = "postgres", target = "postgres://h/db" },
  { "psql", "postgres://h/db", "-X", "-v", "ON_ERROR_STOP=1", "-P", "pager=off", "-P", "null=∅" }
)
eq(
  "command: sqlite3 with headers in boxes",
  sqlrun.command { kind = "sqlite", target = "a.db" },
  { "sqlite3", "-bail", "-header", "-box", "a.db" }
)

-- ── project setup presets ────────────────────────────────────────────────────

local ls = require "langsetup"
eq("parse: a // header for JS-like files", ls.parse("x", "// what\n// target: a.js\nbody\n").target, "a.js")
eq("parse: JSON gets no comment", ls.parse("x", "// what\n// target: a.json\n{}\n").body, "{}\n")
ok(
  "parse: .nvmrc and .python-version get no comment either",
  ls.bare ".nvmrc" and ls.bare ".python-version" and ls.bare ".swift-format" and not ls.bare "ruff.toml"
)
eq(
  "render: placeholders filled, unknown ones listed",
  { ls.render("a {{x}} {{y}}", { x = "1" }) },
  { "a 1 {{y}}\n", { "y" } }
)
local fake_roots = {
  typescript = { ["package.json"] = '{"name":"web","engines":{"node":">=22"}}', ["pnpm-lock.yaml"] = "" },
  python = { ["pyproject.toml"] = '[project]\nname = "my-app"\nrequires-python = ">=3.13"\n', ["uv.lock"] = "" },
  rust = { ["Cargo.toml"] = '[package]\nname = "calc"\nedition = "2024"\n' },
  swift = { ["Package.swift"] = '// swift-tools-version: 6.1\nlet package = Package(name: "Calc")\n' },
}
for _, lang in ipairs(ls.LANGS) do
  local l = ls.lang(lang)
  local r = base .. "/setup-" .. lang
  for f, text in pairs(fake_roots[lang]) do
    write(r .. "/" .. f, text)
  end
  local vars = l.vars(r)
  local keys = {}
  for _, topic in ipairs(l.topics) do
    ok(
      lang .. " " .. topic.id .. ": a key of its own",
      not keys[topic.key] and topic.key ~= "p" and topic.key ~= "m" and topic.key ~= "g"
    )
    keys[topic.key] = true
    local variants = ls.variants(lang, topic.id)
    ok(
      lang .. " " .. topic.id .. ": has presets, its default among them",
      #variants > 0 and vim.iter(variants):any(function(v)
        return v.name == topic.default
      end)
    )
    for _, v in ipairs(variants) do
      local text, unknown = ls.render(v.body, vars)
      eq(lang .. " " .. topic.id .. "/" .. v.name .. ": every placeholder filled", unknown, {})
      if ls.bare(v.target) and (v.target:match "%.json$" or v.target == ".swift-format") then
        ok(lang .. " " .. topic.id .. "/" .. v.name .. ": valid JSON", pcall(vim.json.decode, text))
      end
      if ls.bare(v.target) then
        ok(lang .. " " .. topic.id .. "/" .. v.name .. ": no comment written into it", not text:find "^%s*[#/]")
      end
    end
  end
end
local tsv = ls.lang("typescript").vars(base .. "/setup-typescript")
eq(
  "typescript vars: name, node from engines, the package manager's commands",
  { tsv.name, tsv.node, tsv.pm, tsv.install },
  { "web", "22", "pnpm", "pnpm install --frozen-lockfile" }
)
local pyv = ls.lang("python").vars(base .. "/setup-python")
eq(
  "python vars: name, package, python, ruff's target",
  { pyv.name, pyv.package, pyv.python, pyv.pyver },
  { "my-app", "my_app", "3.13", "313" }
)
eq("rust vars", { ls.lang("rust").vars(base .. "/setup-rust").edition }, { "2024" })
eq(
  "swift vars",
  { ls.lang("swift").vars(base .. "/setup-swift").name, ls.lang("swift").vars(base .. "/setup-swift").swift },
  { "Calc", "6.1" }
)
local made = base .. "/made"
vim.fn.mkdir(made, "p")
local v = ls.variants("python", "pythonversion")[1]
eq(
  "write: the file, filled",
  { ls.write(made, v, { python = "3.13" }) ~= nil, vim.fn.readfile(made .. "/.python-version") },
  { true, { "3.13" } }
)
eq("write: never overwrites", select(2, ls.write(made, v, { python = "3.12" })), ".python-version is already there")

-- ── small pure helpers of the menus ──────────────────────────────────────────

package.loaded["utils.terminal"] = { run = function() end }
local tsa = require "languages.actions.typescript"
eq(
  "tsc errors as quickfix entries",
  tsa.tsc_items({ "src/a.ts(12,5): error TS2322: Type 'string' is not assignable to type 'number'.", "noise" }, "/p"),
  {
    {
      filename = "/p/src/a.ts",
      lnum = 12,
      col = 5,
      text = "TS2322: Type 'string' is not assignable to type 'number'.",
      type = "E",
    },
  }
)
local dbg = require "langdebug"
eq("cargo executables: the test binaries or the bins of a build", {
  dbg.cargo_executables({
    '{"reason":"compiler-artifact","target":{"kind":["lib"]},"profile":{"test":true},"executable":"/t/calc-123"}',
    '{"reason":"compiler-artifact","target":{"kind":["bin"]},"profile":{"test":false},"executable":"/t/calc"}',
    '{"reason":"build-finished","success":true}',
  }, "test"),
  dbg.cargo_executables(
    { '{"reason":"compiler-artifact","target":{"kind":["bin"]},"profile":{"test":false},"executable":"/t/calc"}' },
    "bin"
  ),
}, { { "/t/calc-123" }, { "/t/calc" } })
ok(
  "debug maps: under D, the same in every language",
  vim.iter(dbg.maps "python"):all(function(m)
    return m[1]:sub(1, 1) == "D"
  end)
)

vim.fn.delete(base, "rf")
print(("%d/%d passed"):format(total - fails, total))
if fails == 0 then
  print "ALL OK"
else
  print(("FAILURES: %d"):format(fails))
end
vim.cmd "qa!"
