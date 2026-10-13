-- Tests for the agent's testing feature (<leader>aT) and the lenses (<leader>aL): per-language conventions, destination
-- (end of the test file), token-saving gates, running the test, gaps and the whole flow through the
-- pipeline with a fake backend. Hermetic: project in a temporary directory, in-memory state, no network or tokens.
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
local function wait(fn, ms)
  return vim.wait(ms or 8000, fn, 20)
end

local conv = require "agent.tests.convention"
local run = require "agent.tests.run"
local dest = require "agent.tests.target"

-- ── conventions (pure) ──────────────────────────────────────────────────────
local proj = vim.fn.tempname()
vim.fn.mkdir(proj .. "/src", "p")
vim.fn.mkdir(proj .. "/pkg/tests", "p")
vim.fn.mkdir(proj .. "/lib/ui", "p")
vim.fn.mkdir(proj .. "/app/src/main/java/x", "p")
vim.fn.writefile({}, proj .. "/.git") -- root marker (a file is enough for vim.fs.root)
vim.fn.writefile({ '{ "devDependencies": { "vitest": "1" } }' }, proj .. "/package.json")
vim.fn.writefile({ "name: app", "dependencies:", "  flutter:" }, proj .. "/pubspec.yaml")

local function loc(rel, lang)
  local info, why = conv.locate(proj .. "/" .. rel, lang)
  return info and { vim.fn.fnamemodify(info.path, ":s?" .. proj .. "/??"), info.framework:match "^%S+", info.inline }
    or { nil, why }
end
eq("locate go: <name>_test.go next to the code", loc("pkg/store.go", "go")[1], "pkg/store_test.go")
eq("locate go: testing by default", loc("pkg/store.go", "go")[2], "Go")
eq(
  "locate ts: .test. and vitest according to package.json",
  { loc("src/a.ts", "typescript")[1], loc("src/a.ts", "typescript")[2] },
  { "src/a.test.ts", "vitest" }
)
vim.fn.writefile({}, proj .. "/src/other.spec.ts")
eq("locate ts: if the folder already uses .spec., it follows that", loc("src/a.ts", "typescript")[1], "src/a.spec.ts")
eq("locate python: the project's tests/ if it exists", loc("pkg/mod.py", "python")[1], "pkg/tests/test_mod.py")
eq("locate lua: _spec.lua", loc("lib/x.lua", "lua")[1], "lib/x_spec.lua")
eq(
  "locate rust: in the same file",
  { loc("src/lib.rs", "rust")[1], loc("src/lib.rs", "rust")[3] },
  { "src/lib.rs", true }
)
eq(
  "locate dart: lib/ becomes test/ and flutter_test",
  { loc("lib/ui/btn.dart", "dart")[1], loc("lib/ui/btn.dart", "dart")[2] },
  { "test/ui/btn_test.dart", "flutter_test" }
)
eq(
  "locate java: src/main -> src/test with Test suffix",
  loc("app/src/main/java/x/Foo.java", "java")[1],
  "app/src/test/java/x/FooTest.java"
)
eq("locate: language without a convention", loc("a.zig", "zig")[2]:find("no test convention", 1, true) ~= nil, true)

eq("is_test_file", {
  conv.is_test_file "/p/a_test.go",
  conv.is_test_file "/p/a.test.ts",
  conv.is_test_file "/p/a.spec.tsx",
  conv.is_test_file "/p/test_a.py",
  conv.is_test_file "/p/a_spec.lua",
  conv.is_test_file "/p/src/test/java/FooTest.java",
  conv.is_test_file "/p/a.go",
  conv.is_test_file "/p/testing.go",
}, { true, true, true, true, true, true, false, false })

local go_cmd = conv.command(proj .. "/pkg/store_test.go", "go", "TestX")
eq(
  "command go: the folder's package and the exact test",
  go_cmd.cmd,
  { "go", "test", "./pkg", "-count=1", "-run", "^TestX$" }
)
eq(
  "command ts: vitest with -t",
  conv.command(proj .. "/src/a.test.ts", "typescript", "adds").cmd,
  { "npx", "--no-install", "vitest", "run", "src/a.test.ts", "-t", "adds" }
)
eq("command python: pytest -k", conv.command(proj .. "/pkg/test_a.py", "python", "test_a").cmd[3], "pytest")
eq(
  "command: language without a known runner",
  select(2, conv.command(proj .. "/a.lua", "lua", nil)):find("don't know how", 1, true) ~= nil,
  true
)

eq("run.clean: no colors or noise from what passes, with a cap", {
  run.clean "\27[31mFAIL\27[0m x\n=== RUN T\n--- PASS: T\nok  pkg 0.1s\n\n",
  #run.clean(("boom line\n"):rep(1000)) <= 2600,
}, { "FAIL x", true })

-- ── temporary Go project ─────────────────────────────────────────────────────
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local function write(name, lines)
  vim.fn.writefile(lines, dir .. "/" .. name)
end
write("go.mod", { "module example.com/p", "", "go 1.21" })
write("store.go", {
  "package p", -- 1
  "", -- 2
  'import "errors"', -- 3
  "", -- 4
  'var ErrEmpty = errors.New("empty")', -- 5
  "", -- 6
  "type Note struct{ Title string }", -- 7
  "", -- 8
  "type Repo interface {", -- 9
  "\tGet(id int) (*Note, error)", -- 10
  "\tSave(n *Note) error", -- 11
  "}", -- 12
  "", -- 13
  "func Rename(r Repo, id int, title string) error {", -- 14
  "\tn, err := r.Get(id)", -- 15
  "\tif err != nil {", -- 16
  "\t\treturn err", -- 17
  "\t}", -- 18
  '\tif title == "" {', -- 19
  "\t\treturn ErrEmpty", -- 20
  "\t}", -- 21
  "\tn.Title = title", -- 22
  "\treturn r.Save(n)", -- 23
  "}", -- 24
  "", -- 25
  "func Tiny() int { return 1 }", -- 26
  "", -- 27
  "func Helper(a, b int) int {", -- 28
  "\tif a > b {", -- 29
  "\t\treturn a", -- 30
  "\t}", -- 31
  "\treturn b", -- 32
  "}", -- 33
})
write("query.go", {
  "package p", -- 1
  "", -- 2
  'import "database/sql"', -- 3
  "", -- 4
  "func Find(db *sql.DB, name string) error {", -- 5
  '\trows, err := db.Query("SELECT * FROM t WHERE n=\'" + name + "\'")', -- 6
  "\tif err != nil {", -- 7
  "\t\treturn err", -- 8
  "\t}", -- 9
  "\tdefer rows.Close()", -- 10
  "\tfor rows.Next() {", -- 11
  "\t}", -- 12
  "\treturn nil", -- 13
  "}", -- 14
})
vim.cmd.cd(dir)
vim.fn.system { "git", "-C", dir, "init", "-q" }
vim.fn.system { "git", "-C", dir, "-c", "user.email=t@t", "-c", "user.name=t", "add", "-A" }
vim.fn.system {
  "git",
  "-C",
  dir,
  "-c",
  "user.email=t@t",
  "-c",
  "user.name=t",
  "-c",
  "commit.gpgsign=false",
  "commit",
  "-qm",
  "base",
}

-- fake backend + in-memory state + inline input without a window
local agent_state = require "agent.state"
local real_get, real_set = agent_state.get, agent_state.set
local store = { backend = "fakeagent" }
agent_state.get = function(k)
  return store[k]
end
agent_state.set = function(k, v)
  store[k] = v
end
require("agent.runs.store").use(vim.fn.tempname() .. ".jsonl")
require("agent.persist").use(vim.fn.tempname() .. ".json")
local FAKE = { text = "", calls = 0 }
require("agent.backends").register("fakeagent", {
  name = "fakeagent",
  label = "Fake",
  available = function()
    return true
  end,
  models = function(cb)
    cb {}
  end,
  build = function(req)
    FAKE.req, FAKE.calls = req, FAKE.calls + 1
    return { cmd = { "printf", "%s", FAKE.text }, cwd = "/tmp" }
  end,
  parser = function()
    local buf = {}
    return {
      feed = function(chunk)
        buf[#buf + 1] = chunk
        return chunk
      end,
      finish = function(code)
        if code ~= 0 then
          return { ok = false, err = "boom" }
        end
        return { ok = true, text = table.concat(buf), usage = { tokens_in = 100, tokens_out = 20, cost = 0.0004 } }
      end,
    }
  end,
})
local ui_prompt = require "agent.ui.prompt"
ui_prompt.ask = function(_, _, _, cb)
  cb ""
end
local notes = {}
vim.notify = function(msg)
  notes[#notes + 1] = msg
end
local function last_note()
  return notes[#notes] or ""
end

local function open(name)
  vim.cmd("silent edit " .. dir .. "/" .. name)
  vim.bo.filetype = "go"
  return vim.api.nvim_get_current_buf()
end
local function at(line)
  vim.api.nvim_win_set_cursor(0, { line, 0 })
end
local function idle()
  return wait(function()
    return #require("agent.jobs").running() == 0
  end)
end

local tests = require "agent.tests"
local replace = require "agent.output.replace"

-- ── destination: the end of the test file ─────────────────────────────────
local src = open "store.go"
at(14)
local subject = require("agent.context.target").resolve(src, "function")
local tgt = dest.retarget(subject)
eq(
  "destination: new file, an empty line as the target",
  { tgt.kind, tgt.path, tgt.lines, tgt.first, tgt.last },
  { "test-file-end", "store_test.go", { "" }, 1, 1 }
)
eq("destination: the code under test keeps its test info", subject.tests.exists, false)
eq("merge: empty file = the code as is", dest.merge({ "package p" }, tgt), { "package p" })
eq(
  "merge: file with content = what was there + blank line + the new code",
  dest.merge({ "func B() {}" }, { lines = { "}" } }),
  { "}", "", "func B() {}" }
)
eq("merge: without new code nothing changes", dest.merge({}, { lines = { "}" } }), { "}" })
eq(
  "check: a small function does not deserve a test",
  dest.check({ kind = "function", buf = src, lines = { "func Tiny() int { return 1 }" } }):find("too small", 1, true)
    ~= nil,
  true
)
at(26)
vim.cmd "bwipeout! store_test.go"

-- ── write: new file, whole flow ───────────────────────────────────────
FAKE.text =
  '```go\npackage p\n\nimport "testing"\n\nfunc TestRename(t *testing.T) {}\n```\nneeds-import: errors\nnote: assumed a fake Repo'
src = open "store.go"
at(14)
tests.run "write"
eq(
  "write: opens the test file to the side with the proposal",
  wait(function()
    return vim.api.nvim_buf_get_name(0):match "store_test%.go$" ~= nil
  end),
  true
)
local prompt = FAKE.req.prompt
eq("write: the prompt carries testing, subject and the target is the end of the test file", {
  prompt:find("<testing>\ntest file: store_test.go (NEW", 1, true) ~= nil,
  prompt:find("<subject>", 1, true) ~= nil and prompt:find("func Rename(r Repo", 1, true) ~= nil,
  prompt:find('<target lines="1-1" kind="test-file-end"', 1, true) ~= nil,
  prompt:find("<testfile>", 1, true) == nil, -- new file: nothing to summarize
}, { true, true, true, true })
eq(
  "write: the system asks for ONLY the new code",
  FAKE.req.system:find("output ONLY new test code to append", 1, true) ~= nil,
  true
)
eq(
  "write: the spinner/proposal belongs to the destination and does NOT create the file yet",
  vim.uv.fs_stat(dir .. "/store_test.go"),
  nil
)
replace.accept()
eq(
  "write: accepting puts the code in the test file",
  vim.api.nvim_buf_get_lines(0, 0, -1, false),
  { "package p", "", 'import "testing"', "", "func TestRename(t *testing.T) {}" }
)
vim.cmd "silent write" -- the directory already exists; if it did not, BufWritePre creates it
eq("write: saving creates the file", vim.uv.fs_stat(dir .. "/store_test.go") ~= nil, true)
vim.cmd "close"

-- ── write: existing file, only what is missing ──────────────────────────────
write("store_test.go", {
  "package p",
  "",
  'import "testing"',
  "",
  "func TestRenameOK(t *testing.T) {",
  '\tif err := Rename(nil, 1, "x"); err == nil {',
  '\t\tt.Log("Rename called")',
  "\t}",
  "}",
  "",
  "func TestOther(t *testing.T) {",
  "\tt.Log(1)",
  "\tt.Log(2)",
  "}",
})
vim.cmd "bwipeout! store_test.go"
FAKE.text = "```go\nfunc TestRenameEmpty(t *testing.T) {\n}\n```"
src = open "store.go"
at(14)
tests.run "write"
wait(function()
  return vim.api.nvim_buf_get_name(0):match "store_test%.go$" ~= nil
end)
prompt = FAKE.req.prompt
eq("write existing: header, names, and what already covers the function (add only what is missing)", {
  prompt:find("exists: append to it", 1, true) ~= nil,
  prompt:find("-- existing tests: TestRenameOK, TestOther", 1, true) ~= nil,
  prompt:find("already cover Rename (add only what is missing)", 1, true) ~= nil,
  prompt:find("func TestRenameOK", 1, true) ~= nil,
  prompt:find('<target lines="14-14"', 1, true) ~= nil,
}, { true, true, true, true, true })
eq("write existing: the prompt does not carry the whole test file", prompt:find("func TestOther", 1, true), nil)
replace.accept()
local tl = vim.api.nvim_buf_get_lines(0, 0, -1, false)
eq(
  "write existing: appended at the end, separated by a blank line",
  { tl[#tl - 4], tl[#tl - 3], tl[#tl - 2], tl[#tl - 1], tl[#tl] },
  { "\tt.Log(2)", "}", "", "func TestRenameEmpty(t *testing.T) {", "}" }
)
vim.cmd "silent write"
vim.cmd "close"

-- ── write on a test file, and without a convention ──────────────────────
vim.cmd("silent edit " .. dir .. "/store_test.go")
at(5)
local calls = FAKE.calls
tests.run "write"
eq(
  "write: on a test file it warns and spends nothing",
  { last_note():find("already a test file", 1, true) ~= nil, FAKE.calls },
  { true, calls }
)

-- ── mock ─────────────────────────────────────────────────────────────────────
FAKE.text = "```go\ntype fakeRepo struct{}\n```"
src = open "store.go"
at(10)
tests.run "mock"
wait(function()
  return vim.api.nvim_buf_get_name(0):match "store_test%.go$" ~= nil
end)
eq("mock: the subject is the interface (its methods travel) and it uses the light model", {
  FAKE.req.prompt:find("Get(id int) (*Note, error)", 1, true) ~= nil,
  FAKE.req.system:find("test double", 1, true) ~= nil,
  require("agent.selection").tier_of(require("agent.tests.actions").get "mock"),
}, { true, true, "light" })
replace.reject()
vim.cmd "close"

-- ── fix: runs the test and only spends if it fails ───────────────────────────────
if vim.fn.executable "go" == 1 then
  write("store_test.go", {
    "package p",
    "",
    'import "testing"',
    "",
    "func TestPasses(t *testing.T) {",
    "\tif Helper(1, 2) != 2 {",
    '\t\tt.Fatal("no")',
    "\t}",
    "}",
    "",
    "func TestBroken(t *testing.T) {",
    "\tif Helper(1, 2) != 99 {",
    '\t\tt.Fatal("helper returned the wrong value")',
    "\t}",
    "}",
  })
  vim.cmd "bwipeout! store_test.go"
  vim.cmd("silent edit " .. dir .. "/store_test.go")
  at(6)
  calls = FAKE.calls
  tests.run "fix"
  eq("fix: a passing test does not call the model (0 tokens)", wait(function()
    return last_note():find("already passes", 1, true) ~= nil
  end) and FAKE.calls == calls, true)
  FAKE.text =
    '```go\nfunc TestBroken(t *testing.T) {\n\tif Helper(1, 2) != 2 {\n\t\tt.Fatal("helper returned the wrong value")\n\t}\n}\n```'
  at(12)
  tests.run "fix"
  eq(
    "fix: a failing test sends its real output and proposes the fix",
    wait(function()
      return FAKE.calls == calls + 1 and #require("agent.jobs").running() == 0
    end)
      and FAKE.req.prompt:find("<test_output>", 1, true) ~= nil
      and FAKE.req.prompt:find("helper returned the wrong value", 1, true) ~= nil
      and FAKE.req.prompt:find("$ go test ./ -count=1 -run ^TestBroken$", 1, true) ~= nil,
    true
  )
  replace.reject()
  vim.cmd("silent edit! " .. dir .. "/store.go")
  at(14)
  calls = FAKE.calls
  tests.run "fix"
  eq(
    "fix: outside a test file it warns and spends nothing",
    { last_note():find("put the cursor in a test function", 1, true) ~= nil, FAKE.calls },
    { true, calls }
  )
else
  print "skip go not installed: the `fix` test is skipped"
end

-- ── gaps (local) ───────────────────────────────────────────────────────────
src = open "store.go"
tests.gaps()
local qf = vim.fn.getqflist { items = 1, title = 1 }
local names = vim.tbl_map(function(i)
  return i.text:match "^(%w+)"
end, qf.items)
table.sort(names)
eq(
  "gaps: public functions with no test naming them",
  { qf.title, names },
  { "Untested functions (3 of 4)", { "Find", "Rename", "Tiny" } }
)
vim.cmd "cclose"

-- ── lenses ───────────────────────────────────────────────────────────────────
local lenses = require "agent.lenses.actions"
local list = lenses.list()
eq("lenses: 5, distinct keys, they come out as diagnostics with their source", {
  #list,
  #vim.fn.uniq(vim.fn.sort(vim.tbl_map(function(a)
    return a.key
  end, list))),
  vim.tbl_map(function(a)
    return a.output .. ":" .. a.source
  end, list),
}, { 5, 5, { "findings:security", "findings:performance", "findings:concurrency", "findings:errors", "findings:api" } })
eq(
  "lenses: security and concurrency use the main model; the rest, the light one",
  vim.tbl_map(function(a)
    return require("agent.selection").tier_of(a)
  end, list),
  { "main", "light", "main", "light", "light" }
)
eq("lenses: action name lens_<x> (to reassign the tier)", lenses.get("security").name, "lens_security")

src = open "store.go"
at(14)
local rename = require("agent.context.target").resolve(src, "function")
eq(
  "gate: security does not call the model if there is nothing security-related",
  lenses.get("security").check(rename):find("skipped (0 tokens)", 1, true) ~= nil,
  true
)
eq(
  "gate: concurrency neither without threads/locks",
  lenses.get("concurrency").check(rename):find("skipped", 1, true) ~= nil,
  true
)
eq("gate: errors does pass (there is err)", lenses.get("errors").check(rename), nil)
local query_buf = open "query.go"
at(5)
local find = require("agent.context.target").resolve(query_buf, "function")
eq("gate: security passes with SQL", lenses.get("security").check(find), nil)
eq(
  "api: without uncommitted changes there is nothing to compare against",
  lenses.get("api").check(find):find("no uncommitted changes", 1, true) ~= nil,
  true
)

-- whole flow: two lenses coexist and repeating one only replaces its own
local fns = vim.api.nvim_create_namespace "agent.findings"
FAKE.text = "L6|error|SQL built by concatenating name: use a placeholder"
at(5)
require("agent.lenses").run "security"
idle()
FAKE.text = "L11|warn|loop without a limit"
require("agent.lenses").run "performance"
idle()
local function srcs()
  local out = vim.tbl_map(function(d)
    return d.source
  end, vim.diagnostic.get(query_buf, { namespace = fns }))
  table.sort(out)
  return out
end
eq("lenses: two lenses coexist in the same function", srcs(), { "performance", "security" })
eq("lenses: the prompt carries the focus and the numbered code", {
  FAKE.req.system:find("Report ONLY performance problems", 1, true) ~= nil,
  FAKE.req.prompt:find("6: ", 1, true) ~= nil,
}, { true, true })
FAKE.text = "L6|error|string concatenation in SQL again"
require("agent.lenses").run "security"
idle()
local d2 = vim.diagnostic.get(query_buf, { namespace = fns })
table.sort(d2, function(a, b)
  return a.source < b.source
end)
eq(
  "lenses: repeating one only replaces its own findings",
  { #d2, d2[1].source, d2[2].source, d2[2].message },
  { 2, "performance", "security", "string concatenation in SQL again" }
)

-- api: with uncommitted changes it does run, and the diff travels
vim.fn.writefile({
  "package p",
  "",
  'import "database/sql"',
  "",
  "func Find(db *sql.DB, name string, limit int) error {",
  '\trows, err := db.Query("SELECT * FROM t")',
  "\tif err != nil {",
  "\t\treturn err",
  "\t}",
  "\tdefer rows.Close()",
  "\tfor rows.Next() {",
  "\t}",
  "\treturn nil",
  "}",
}, dir .. "/query.go")
vim.cmd "silent edit!"
at(5)
FAKE.text = "L5|warn|new required parameter breaks every caller"
calls = FAKE.calls
require("agent.lenses").run "api"
idle()
eq("api: with changes it runs and sends the function's diff (-/+)", {
  FAKE.calls == calls + 1,
  FAKE.req.prompt:find("<changes>", 1, true) ~= nil,
  FAKE.req.prompt:find("-func Find(db *sql.DB, name string) error {", 1, true) ~= nil,
  FAKE.req.prompt:find("+func Find(db *sql.DB, name string, limit int) error {", 1, true) ~= nil,
}, { true, true, true, true })

-- gate: a lens that does not apply costs nothing
calls = FAKE.calls
at(14 - 9) -- inside Find
vim.api.nvim_set_current_buf(src)
at(14)
require("agent.lenses").run "concurrency"
eq("gate: a lens that does not apply does not call the model", FAKE.calls, calls)

agent_state.get, agent_state.set = real_get, real_set
require("agent.runs.store").use(nil)
require("agent.persist").use(nil)
vim.cmd.cd "/"
vim.fn.delete(dir, "rf")
vim.fn.delete(proj, "rf")
print(fails == 0 and "\nALL OK" or ("\nFAILURES: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
