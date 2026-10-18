-- Tests of the build's user harness (nvim/lua/agent/kit/build): clean answers (clean.lua), the plan's exports nobody uses
-- (wiring.lua), the wiring map in the plan, and the use phase (use/: launch detection, scenarios, the drivers, the free
-- checks and the verdict, the whole flow with a fake model). The drivers run for real when their tool is here (tmux,
-- Playwright): a tiny app in a temp folder, no network, no tokens.
--   XDG_STATE_HOME=$(mktemp -d) nvim -u NONE --headless -c "luafile scripts/test-kit-use.lua"
local root = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
vim.opt.rtp:prepend(root .. "/nvim")
package.path = root .. "/nvim/lua/?.lua;" .. root .. "/nvim/lua/?/init.lua;" .. package.path

local fails, total, skipped = 0, 0, {}
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

local notes = {}
package.loaded["utils.log"] = {
  info = function(m)
    notes[#notes + 1] = "info: " .. m
  end,
  warn = function(m)
    notes[#notes + 1] = "warn: " .. m
  end,
  error = function(m)
    notes[#notes + 1] = "error: " .. m
  end,
}

local base = vim.fn.tempname()
local function write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "w"))
  f:write(text or "")
  f:close()
end
local function read(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local text = f:read "*a"
  f:close()
  return text
end
local function project(name, files)
  local dir = base .. "/" .. name
  vim.fn.mkdir(dir, "p")
  for rel, text in pairs(files or {}) do
    write(dir .. "/" .. rel, text)
  end
  return dir
end
--- Runs a coroutine body (use/async) to the end and returns what it returned
local function sync(fn, timeout)
  local out, finished
  require("agent.kit.build.use.async").run(fn, function(okay, ...)
    out, finished = { okay, ... }, true
  end)
  vim.wait(timeout or 20000, function()
    return finished
  end, 20)
  return out or {}
end

-- ── clean: a model's answer as a file ────────────────────────────────────────

local clean = require "agent.kit.build.clean"
eq(
  "clean: prose around a fence → the fence",
  clean.file("I'll make the file now.\n\n```go\npackage domain\n\nvar X = 1\n```\n\nThis file declares X.", "a.go"),
  "package domain\n\nvar X = 1\n"
)
eq(
  "clean: leaked tool-call markup and echoed tags out",
  clean.file(
    '<file path="a.go">\npackage ui\n\nfunc A() {}\n</file>\n</｜｜DSML｜｜ parameter>\n</｜｜DSML｜｜ invoke>',
    "a.go"
  ),
  "package ui\n\nfunc A() {}\n"
)
eq(
  "clean: chatter before a Go package clause out",
  clean.file(
    "The file looks correct per the plan.\nI'll return it unchanged.\npackage config\n\nfunc Load() {}",
    "c.go"
  ),
  "package config\n\nfunc Load() {}\n"
)
eq(
  "clean: a Markdown file keeps its own fences",
  clean.file("# Readme\n\n```sh\ngo run ./cmd/app\n```\n", "README.md"),
  "# Readme\n\n```sh\ngo run ./cmd/app\n```\n"
)
eq(
  "clean: a fence around a whole Markdown answer goes",
  clean.file("```markdown\n# R\n\nx\n```", "README.md"),
  "# R\n\nx\n"
)
eq(
  "clean: JSON starts at its brace",
  clean.file('Here is package.json:\n{"name": "x"}', "package.json"),
  '{"name": "x"}\n'
)
eq("clean: code that starts like a word is kept", clean.file("Now = time.Now()\n", "a.py"), "Now = time.Now()\n")
eq("clean problem: a clean file", clean.problem("package a\n", "a.go"), nil)
ok("clean problem: markup left", (clean.problem("package a\n</file>\n", "a.go") or ""):find "markup")
ok("clean problem: Go without package", (clean.problem("func A() {}\n", "a.go") or ""):find "package")
ok("clean problem: invalid JSON", (clean.problem("{nope\n", "package.json") or ""):find "JSON")
ok("clean problem: a sentence first", (clean.problem("Sure, here it is\nx = 1\n", "a.py") or ""):find "sentence")
local prompt = require "agent.kit.build.prompt"
local again =
  prompt.again({ action = "kit_build_file", prompt = "Write `a.go`", cache = true }, "it is wrapped in a ``` fence")
ok(
  "again: the reason and the rule are added, the cache is off",
  again.prompt:find("wrapped in a", 1, true) and again.cache == false
)

-- ── wiring: what the plan exports and nobody calls ───────────────────────────

local wiring = require "agent.kit.build.wiring"
eq(
  "wiring name: a method",
  wiring.names "Calculator.Expression() string — e.g. 2 + 3",
  { { name = "Expression", member = true, call = true } }
)
eq("wiring name: a Go receiver", wiring.name "func (c Calculator) Display() string", "Display")
eq("wiring name: a JS export", wiring.name "export function evaluate(expr: string): number — the result", "evaluate")
eq(
  "wiring name: a list of values",
  vim.tbl_map(function(n)
    return n.name
  end, wiring.names "Title, Subtitle, Expression styles"),
  { "Title", "Subtitle", "Expression" }
)
eq("wiring name: prose is no name", wiring.name "Handles all the keys of the app", nil)
eq("wiring name: framework hooks never count", wiring.name "Model.View() string — pure", nil)
local wplan = {
  files = {
    {
      path = "domain/calc.go",
      exports = {
        "Calculator.Expression() string — the expression",
        "Calculator.Display() string — the entry",
        "New() Calculator — idle",
      },
    },
    { path = "ui/styles.go", exports = { "Display, Muted styles" } },
    { path = "ui/view.go", exports = { "View(c Calculator) string — the screen" } },
    { path = "main.go", exports = {} },
  },
}
local wfiles = {
  ["domain/calc.go"] = 'package domain\n\nfunc New() Calculator { return Calculator{} }\nfunc (c Calculator) Display() string { return "0" }\n\n// Expression is what was typed\nfunc (c Calculator) Expression() string { return "" }\n',
  ["domain/calc_test.go"] = "package domain\nfunc TestE(t *testing.T) { _ = New().Expression() }\n",
  ["ui/styles.go"] = "package ui\nvar Display = lipgloss.NewStyle()\nvar Muted = lipgloss.NewStyle()\n",
  ["ui/view.go"] = "package ui\n// Expression is not shown yet\nfunc View(c domain.Calculator) string { return Display.Render(c.Display()) }\n",
  ["main.go"] = "package main\nfunc main() { ui.View(domain.New()) }\n",
}
local found = wiring.find(wplan, wfiles)
eq(
  "wiring: the method only a test calls, and the style nobody uses (a comment is not a use)",
  vim.tbl_map(function(u)
    return { u.path, u.line, u.name, u.tests, u.call }
  end, found),
  { { "domain/calc.go", 7, "Expression", true, true }, { "ui/styles.go", 3, "Muted", false, false } }
)
local calls, values = wiring.split(found)
eq("wiring: behaviours fail the check, values are context", { #calls, #values }, { 1, 1 })
ok(
  "wiring report: path:line first, blamed on the declaring file",
  wiring.report(calls):find "^domain/calc.go:7: Expression is promised"
)
wfiles["ui/view.go"] = wfiles["ui/view.go"]:gsub("c%.Display%(%)", "c.Display() + c.Expression()")
eq("wiring: called by the view = wired", #wiring.split(wiring.find(wplan, wfiles)), 0)
local bverify = require "agent.kit.build.verify"
eq(
  "wiring report: verify.blame maps it to the planned file",
  vim.tbl_keys(bverify.blame(wiring.report(calls), { "domain/calc.go", "ui/view.go" })),
  { "domain/calc.go" }
)

-- ── edits: a fix as edit blocks ─────────────────────────────────────────────
do
  local edits = require "agent.kit.build.edits"
  local text = "import type { Op as T } from './calc';\n\nexport type Op = '+';\n\nexport const x = 1;\n"
  eq(
    "edits: a deletion (empty REPLACE), trailing spaces ignored",
    edits.apply(text, "<<<<<<< SEARCH\nimport type { Op as T } from './calc';   \n=======\n>>>>>>> REPLACE"),
    "\nexport type Op = '+';\n\nexport const x = 1;\n"
  )
  eq(
    "edits: two blocks in order",
    edits.apply(
      "a\nb\nc\n",
      "<<<<<<< SEARCH\na\n=======\nA\n>>>>>>> REPLACE\n<<<<<<< SEARCH\nc\n=======\nC\nC2\n>>>>>>> REPLACE"
    ),
    "A\nb\nC\nC2\n"
  )
  eq(
    "edits: a SEARCH not in the file",
    select(2, edits.apply("a\n", "<<<<<<< SEARCH\nzz\n=======\n>>>>>>> REPLACE")),
    'the SEARCH starting "zz" is not in the file'
  )
  ok(
    "edits: an ambiguous SEARCH",
    select(2, edits.apply("x\nx\n", "<<<<<<< SEARCH\nx\n=======\ny\n>>>>>>> REPLACE")):find("more than one", 1, true)
      ~= nil
  )
  ok(
    "edits: an unclosed block",
    select(2, edits.parse "<<<<<<< SEARCH\na\n=======\nb\n"):find("not closed", 1, true) ~= nil
  )
  eq("edits: UNCHANGED", { edits.unchanged "UNCHANGED\n", edits.unchanged "package a" }, { true, false })
  ok("edits: a one-line answer for a 30-line file is a fragment", edits.shrunk(("x\n"):rep(30), "import x\n") ~= nil)
  eq("edits: a small file may shrink", edits.shrunk("a\nb\n", "a\n"), nil)
  local bprompt = require "agent.kit.build.prompt"
  ok(
    "edits: a fix asks for edit blocks",
    bprompt.fix("a.ts", text, "err", nil, { files = {} }, {}, {}, nil, "x").prompt:find("<<<<<<< SEARCH", 1, true)
      ~= nil
  )
  ok(
    "edits: a new file asks for its whole content",
    bprompt
      .fix("assets/banner.txt", "", "err", nil, { files = {} }, {}, {}, nil, "x").prompt
      :find("does not exist yet", 1, true) ~= nil
  )
  local d = require("agent.kit.build.diagnose").parse(
    '{"diagnosis":"embed","files":[{"path":"internal/ui/banner.go","change":"embed banner.txt"},{"path":"internal/ui/banner.txt","new":true,"change":"the banner"},{"path":"../x","new":true,"change":"no"},{"path":"z.go","change":"not planned, not new"}]}',
    { "internal/ui/banner.go" }
  )
  eq(
    "diagnosis: a file the plan missed is kept when its path is safe, flagged new",
    vim.tbl_map(function(f)
      return { f.path, f.new or false }
    end, d.files),
    { { "internal/ui/banner.go", false }, { "internal/ui/banner.txt", true } }
  )
  eq(
    "go.mod: an invented pseudo-version is dropped, tidy puts the real one back (0 tokens)",
    require("agent.kit.build.verify").drop_versions "go: downloading x\ngo: github.com/charmbracelet/x/exp/teatest@v0.0.0-20250611152503-6e5f2df03d34: invalid version: unknown revision 6e5f2df03d34",
    { "go", "mod", "edit", "-droprequire=github.com/charmbracelet/x/exp/teatest" }
  )
  local dq = require("agent.kit.build.diagnose").request(
    "FAIL x",
    {},
    { files = {} },
    {},
    {},
    '✗ toggle sign · "-1" is not on the screen'
  )
  ok(
    "diagnosis: after a use fix it knows what the user met, and that such a test is wrong",
    dq.prompt:find("<user>", 1, true) and dq.prompt:find("locks the bug in", 1, true)
  )
  ok(
    "diagnosis: without one, no <user>",
    not require("agent.kit.build.diagnose").request("FAIL x", {}, { files = {} }, {}, {}).prompt:find("<user>", 1, true)
  )
  local judge_mod = require "agent.kit.build.use.judge"
  local keypad = '- status: "0"\n- button "7"\n- button "8"\n- button "9"\n- button "="'
  eq(
    "judge: a step that changed one row sends that row only",
    judge_mod.delta(keypad, keypad:gsub('"0"', '"12"')),
    'only these rows changed (the rest as in the step before):\nrow 1: - status: "12"'
  )
  eq("judge: a new screen is sent whole", judge_mod.delta("a\nb", "c\nd"), nil)
  ok(
    "edits: after blocks that do not apply, the one retry asks for the whole file",
    require("agent.kit.build.prompt")
      .again({ prompt = "Fix x" }, "no match", true).prompt
      :find("WHOLE corrected file", 1, true) ~= nil
  )
  eq(
    "DOM: a button wired to a name no script handles",
    require("agent.kit.build.verify").unhandled_actions {
      ["index.html"] = '<button data-action="digit" data-value="7">7</button>\n<button data-action="equals">=</button>\n<button data-op="add">+</button>',
      ["src/view.ts"] = 'switch (action) { case "digit": break; case "evaluate": break }\nconst ops = { add: 1 }',
      ["src/view.test.ts"] = '"equals"',
    },
    {
      'index.html:2: data-action="equals" is handled by no script: pressing it does nothing (handle that name, or use the name the code handles)',
    }
  )
  eq(
    "DOM: data-key names are handler names too; digits and symbols are data",
    require("agent.kit.build.verify").unhandled_actions {
      ["index.html"] = '<button data-key="7">7</button><button data-key="/">÷</button><button data-key="clear">C</button>\n<button data-key="equals">=</button>',
      ["src/view.ts"] = 'const action = key.dataset.key; if (action === "clear") reset()',
    },
    {
      'index.html:2: data-key="equals" is handled by no script: pressing it does nothing (handle that name, or use the name the code handles)',
    }
  )
  ok(
    "judge: the verdict reads the code that wires the interface",
    require("agent.kit.build.use.judge")
      .request({}, "", { files = {} }, {}, '<file path="src/view.ts">x</file>').prompt
      :find("<code>", 1, true) ~= nil
  )
  eq(
    "plan: files tools generate are never planned",
    vim.tbl_map(
      function(f)
        return f.path
      end,
      require("agent.kit.build.plan").parse(vim.json.encode {
        files = {
          { path = "go.mod" },
          { path = "go.sum" },
          { path = "internal/ui/testdata/main.golden" },
          { path = "main.go" },
        },
      }).files
    ),
    { "go.mod", "main.go" }
  )
  eq(
    "judge: a lone digit in not_see is never a failure (the keypad shows it)",
    require("agent.kit.build.use.judge").check(
      { see = {}, not_see = { "0", "Can't divide" } },
      { screen = "button 0\nCan't divide by 0" }
    ),
    { '"Can\'t divide" is on the screen and must not be' }
  )
  ok(
    "clean: edit block markers in a whole file are a problem",
    require("agent.kit.build.clean").problem("const a = 1;\n=======\nconst a = 2;\n>>>>>>> REPLACE\n", "a.ts") ~= nil
  )
  eq(
    "clean: a Markdown underline is not",
    require("agent.kit.build.clean").problem("Title\n=======\n", "README.md"),
    nil
  )
  eq(
    "json: a brace inside a string does not cut the object (Lua's %b{} would)",
    require("agent.kit.build.clean").json 'Here: {"a": "the set {1, 2", "b": [1]} done',
    { a = "the set {1, 2", b = { 1 } }
  )
  eq("json: none", require("agent.kit.build.clean").json "no json here", nil)
  eq("go.mod: nothing invented, no command", require("agent.kit.build.verify").drop_versions "go: finding module", nil)
  ok(
    "go.mod: the file request asks for no require block",
    require("agent.kit.build.prompt")
      .file({ path = "go.mod", purpose = "m", docs = {}, needs = {} }, { files = {} }, {}, {}).prompt
      :find("no require block", 1, true) ~= nil
  )
  local build_mod = require "agent.kit.build"
  ok(
    "signature: two different tsc errors are two failures (no `file:line` in TypeScript's output)",
    build_mod.signature("tsc", "src/a.ts(1,1): error TS6133: 'X' is declared")
      ~= build_mod.signature("tsc", "src/a.test.ts(2,10): error TS2305: no member")
  )
end

-- ── plan: the wiring map ─────────────────────────────────────────────────────

local plan_mod = require "agent.kit.build.plan"
local parsed = plan_mod.parse(vim.json.encode {
  name = "c",
  wiring = {
    {
      req = "FR-2",
      action = "presses + after a number",
      code = "ui.Update → domain.ChooseOperator",
      shows = "view.go: the expression line shows 12 +",
    },
    { req = "FR-3", action = "missing parts" },
  },
  files = { { path = "a.go", purpose = "a" } },
})
eq("plan: wiring rows with all four parts kept", #parsed.wiring, 1)
local system = prompt.system(parsed, { spec = "# S" })
ok("plan: every file request carries the wiring", system:find("FR-2: presses + after a number → ui.Update", 1, true))
ok("plan: the review shows it", require("agent.kit.build").plan_text(parsed):find("## Wiring", 1, true))
ok("prompt: the user rule is in the system prompt", system:find("Built for a user, not for the tests", 1, true))

-- ── launch: what kind of app it is ───────────────────────────────────────────

local launch = require "agent.kit.build.use.launch"
local function kind_of(files, stack)
  local dir = project("launch-" .. vim.fn.sha256(vim.inspect(files)):sub(1, 8), files)
  local l, why = launch.detect(dir, stack, dir .. "/bin/app", "npm")
  return l and l.kind or why, l
end
eq(
  "launch: Go + Bubble Tea = tui",
  kind_of {
    ["go.mod"] = "module c\nrequire github.com/charmbracelet/bubbletea v1.3.0\n",
    ["cmd/app/main.go"] = "package main\nfunc main() {}\n",
  },
  "tui"
)
local _, gl = kind_of {
  ["go.mod"] = "module c\n",
  ["cmd/app/main.go"] = "package main\nfunc main() {}\n",
  ["tools/gen/main.go"] = "package main\n",
}
eq("launch: Go CLI builds cmd/<name> first", { gl.kind, gl.build[5] }, { "cli", "./cmd/app" })
eq(
  "launch: Go server = web",
  kind_of {
    ["go.mod"] = "module c\n",
    ["main.go"] = 'package main\nfunc main() { http.ListenAndServe(":8080", nil) }\n',
  },
  "web"
)
eq(
  "launch: Vite = web",
  kind_of { ["package.json"] = '{"scripts":{"dev":"vite"},"devDependencies":{"vite":"8"}}' },
  "web"
)
eq(
  "launch: a bin = cli",
  kind_of { ["package.json"] = '{"bin":{"calc":"dist/cli.js"},"scripts":{"build":"tsc"}}' },
  "cli"
)
eq("launch: Ink = tui", kind_of { ["package.json"] = '{"bin":"cli.js","dependencies":{"ink":"5"}}' }, "tui")
eq("launch: Electron", kind_of { ["package.json"] = '{"devDependencies":{"electron":"33"}}' }, "electron")
eq(
  "launch: Textual = tui",
  kind_of {
    ["pyproject.toml"] = '[project]\nname="c"\ndependencies=["textual>=1"]\n[project.scripts]\ncalc = "c:main"\n',
  },
  "tui"
)
eq(
  "launch: Rust + Ratatui = tui",
  kind_of { ["Cargo.toml"] = '[package]\nname = "calc"\n\n[dependencies]\nratatui = "0.29"\n' },
  "tui"
)
eq("launch: a static page = web", kind_of { ["index.html"] = "<!doctype html>" }, "web")
local _, al = kind_of { ["app/build.gradle.kts"] = 'android { defaultConfig { applicationId = "dev.calc" } }' }
eq("launch: Android with its application id", { al.kind, al.package }, { "android", "dev.calc" })
ok("launch: nothing to start says why", kind_of({ ["README.md"] = "# x" }):find "no entry point")

-- ── scenarios ────────────────────────────────────────────────────────────────

local scenario = require "agent.kit.build.use.scenario"
local sc = scenario.parse(
  vim.json.encode {
    scenarios = {
      {
        name = "add",
        covers = { "FR-2" },
        steps = {
          { ["do"] = "type", text = "12+", see = { "12 +" }, expect = "the pending operation" },
          { ["do"] = "fly", expect = "unknown action dropped" },
          { ["do"] = "key", key = "Enter", see = { "15" } },
          { ["do"] = "resize", size = "huge" },
        },
      },
      { name = "empty", steps = { { ["do"] = "click" } } },
    },
  },
  "tui"
)
eq(
  "scenarios: unknown actions and bad fields dropped, empty scenarios dropped",
  { #sc, #sc[1].steps, sc[1].size },
  { 1, 2, "80x24" }
)
eq("scenarios: nothing usable = nil", scenario.parse('{"scenarios":[]}', "tui"), nil)
local cli_sc = scenario.parse(
  '{"scenarios":[{"name":"div","steps":[{"do":"run","args":["8","/",0],"exit":1,"see":["zero"]}]}]}',
  "cli"
)
eq(
  "scenarios cli: args as strings, the exit code kept",
  { cli_sc[1].steps[1].args, cli_sc[1].steps[1].exit },
  { { "8", "/", "0" }, 1 }
)
local web_sc = scenario.parse(
  '{"scenarios":[{"name":"w","steps":[{"do":"goto"},{"do":"click","target":{"role":"button","name":"7"}},{"do":"click"}]}]}',
  "web"
)
eq(
  "scenarios web: goto defaults to /, a click needs a target",
  { #web_sc[1].steps, web_sc[1].steps[1].path, web_sc[1].viewport },
  { 2, "/", "1280x800" }
)
eq("describe: a click", scenario.describe(web_sc[1].steps[2]), 'click button "7"')
local sreq = scenario.request(
  "tui",
  parsed,
  { spec = "# S" },
  { ["ui/keys.go"] = "package ui\nvar Add = key.NewBinding()\n" }
)
ok(
  "scenarios request: the driver's actions and the rule that expectations come from the documents",
  sreq.prompt:find('"do":"resize"', 1, true) and sreq.prompt:find("Expectations come ONLY from SPEC.md", 1, true)
)

-- ── free checks and the verdict ──────────────────────────────────────────────

local judge = require "agent.kit.build.use.judge"
eq(
  "check: missing and forbidden text, whitespace and case free",
  judge.check(
    { ["do"] = "type", see = { "12 +", "Total" }, not_see = { "error" } },
    { screen = "│  12   +  │\nERROR: x" }
  ),
  {
    '"Total" is not on the screen',
    '"error" is on the screen and must not be',
  }
)
eq(
  "check: a crash",
  judge.check(nil, { screen = "panic: runtime error\n[exited with 2]" }),
  { "the app crashed or exited with an error" }
)
eq(
  "check: the exit code",
  judge.check({ ["do"] = "run", exit = 1 }, { screen = "x", exit = 0 }),
  { "exit code 0, SPEC.md implies 1" }
)
local f1, f2 = { step = 0, screen = "0" }, { step = 1, screen = "0" }
judge.check({ ["do"] = "key" }, f2, f1)
ok("check: an action with no visible effect is noticed", f2.unchanged)
eq(
  "compact: blank runs counted, trailing blanks dropped",
  judge.compact "a\n\n\n\n\nb\n\nc\n\n\n\n",
  "a\n⋮ 4 blank rows\nb\n\nc"
)
local verdict = judge.parse(
  '{"verdict":"pass","issues":[],"diagnosis":"","files":[{"path":"ui/view.go","change":"x"},{"path":"ui/view_test.go","change":"y"}]}',
  { "ui/view.go", "ui/view_test.go" },
  2
)
eq("verdict: free failures overrule a pass; tests are never the fix", { verdict.pass, #verdict.files }, { false, 1 })
eq(
  "verdict: a minor issue alone passes",
  judge.parse(
    '{"verdict":"pass","issues":[{"scenario":1,"step":2,"severity":"minor","problem":"p"}],"files":[]}',
    {},
    0
  ).pass,
  true
)
eq(
  "verdict: a major issue fails",
  judge.parse('{"verdict":"pass","issues":[{"severity":"major","problem":"p"}],"files":[]}', {}, 0).pass,
  false
)

-- ── drivers: the pure parts ──────────────────────────────────────────────────

local tui = require "agent.kit.build.use.drivers.tui"
eq(
  "tui keys",
  { tui.key "enter", tui.key "Esc", tui.key "ctrl+c", tui.key "Backspace", tui.key "f5", tui.key "x", tui.key "nope" },
  { "Enter", "Escape", "C-c", "BSpace", "F5", "x", nil }
)
local web = require "agent.kit.build.use.drivers.web"
eq(
  "web: the URL a dev server prints",
  web.url_in "\27[32m  ➜  Local:   http://localhost:5173/\27[0m",
  "http://localhost:5173/"
)
eq("web: 0.0.0.0 becomes the loopback", web.url_in "listening on http://0.0.0.0:3000", "http://127.0.0.1:3000/")
local android = require "agent.kit.build.use.drivers.android"
eq(
  "android: ready devices only",
  android.devices "List of devices attached\nemulator-5554\tdevice\nR58M\tunauthorized\n",
  { "emulator-5554" }
)
local nodes =
  android.nodes [[<hierarchy><node text="" resource-id="" class="android.widget.FrameLayout" bounds="[0,0][1080,2400]" clickable="false"/><node text="7" resource-id="dev.calc:id/seven" content-desc="" class="android.widget.Button" bounds="[0,1600][270,1800]" clickable="true" focused="false"/><node text="12 +" resource-id="dev.calc:id/expr" class="android.widget.TextView" bounds="[0,200][1080,300]" clickable="false"/></hierarchy>]]
eq(
  "android: the screen as text",
  android.screen(nodes),
  'Button "7" #seven @0,1600 270x200 clickable\nTextView "12 +" #expr @0,200 1080x100'
)
eq(
  "android: a target by text, then by id",
  { android.find(nodes, { text = "7" }).y1, android.find(nodes, { id = "expr" }).x2 },
  { 1600, 1080 }
)
eq("android: text for input", android.input_text "a b&c", "a%sb\\&c")

-- ── drivers for real (when their tool is here) ───────────────────────────────

local cli = require "agent.kit.build.use.drivers.cli"
local croot = project("cli-app", {})
local cframes = sync(function()
  return cli.play({
    root = croot,
    launch = {
      argv = {
        "sh",
        "-c",
        'if [ "$1" = 0 ]; then echo "error: division by zero" >&2; exit 1; fi; echo "$(( 8 / $1 ))"',
        "calc",
      },
    },
  }, {
    steps = { { ["do"] = "run", args = { "2" } }, { ["do"] = "run", args = { "0" }, exit = 1 } },
  })
end)[2]
eq(
  "cli driver: stdout, stderr and the exit code per run",
  cframes and { cframes[1].screen, cframes[2].screen, cframes[2].exit },
  {
    "4\n[exit 0]",
    "[stderr]\nerror: division by zero\n[exit 1]",
    1,
  }
)

if vim.fn.executable "tmux" == 1 then
  -- a terminal app: shows what was typed, Enter adds the two numbers around +, q quits
  local troot = project("tui-app", {
    ["app.sh"] = [[
stty -icanon -echo
buf=""
draw() { printf '\033[2J\033[H+--------------+\n| %-12s |\n+--------------+\n' "$1"; }
draw "0"
while true; do
  c=$(dd bs=1 count=1 2>/dev/null)
  case "$c" in
    q) exit 0 ;;
    "") draw "$(( ${buf%+*} + ${buf#*+} ))"; buf="" ;;
    *) buf="$buf$c"; draw "$buf" ;;
  esac
done
]],
  })
  local tctx = { root = troot, dir = troot .. "/.use", launch = { argv = { "sh", troot .. "/app.sh" } } }
  vim.fn.mkdir(tctx.dir, "p")
  local tres = sync(function()
    tui.prepare(tctx)
    local frames = tui.play(tctx, {
      size = "40x10",
      steps = {
        { ["do"] = "type", text = "12+3" },
        { ["do"] = "key", key = "Enter" },
        { ["do"] = "resize", size = "30x8" },
        { ["do"] = "type", text = "q" },
      },
    })
    tui.finish(tctx)
    return frames
  end)
  local tf = tres[2] or {}
  eq(
    "tui driver: the first screen, once it settled",
    (tf[1] or {}).screen,
    "+--------------+\n| 0            |\n+--------------+"
  )
  eq(
    "tui driver: typed one key at a time",
    (tf[2] or {}).screen,
    "+--------------+\n| 12+3         |\n+--------------+"
  )
  ok("tui driver: Enter", ((tf[3] or {}).screen or ""):find("| 15", 1, true))
  ok(
    "tui driver: quitting stays on screen with its code",
    ((tf[5] or {}).screen or ""):find("[exited with 0]", 1, true)
  )
else
  skipped[#skipped + 1] = "tui driver (no tmux)"
end

local wctx = {
  root = project("web-app", {
    ["index.html"] = [[<!doctype html><html><body><main><h1>Calc</h1>
<label>Number <input id="n" value=""></label>
<button id="go">Double</button><p id="out" role="status">0</p>
<button id="broken">Broken</button>
<script>
document.getElementById("go").onclick = () => { document.getElementById("out").textContent = String(2 * +document.getElementById("n").value) }
document.getElementById("broken").onclick = () => { notDefined() }
</script></main></body></html>]],
  }),
}
wctx.launch = { kind = "web", static = wctx.root }
wctx.dir = wctx.root .. "/.use"
if web.available(wctx) and vim.fn.executable "python3" == 1 and vim.fn.executable "curl" == 1 then
  local wres = sync(function()
    local err = web.prepare(wctx)
    if err then
      return nil, err
    end
    local frames, perr = web.play(wctx, {
      viewport = "800x600",
      steps = {
        { ["do"] = "fill", target = { label = "Number" }, value = "21" },
        { ["do"] = "click", target = { role = "button", name = "Double" } },
        { ["do"] = "click", target = { role = "button", name = "Broken" } },
        { ["do"] = "click", target = { role = "button", name = "Missing" } },
      },
    }, 1)
    web.finish(wctx)
    return frames, perr
  end, 90000)
  local wf = wres[2]
  if wf then
    ok("web driver: the page as a screen reader reads it", (wf[1].screen or ""):find('heading "Calc"', 1, true))
    ok(
      "web driver: a click changes the page",
      (wf[3].screen or ""):find('status: "42"', 1, true) or (wf[3].screen or ""):find("42", 1, true)
    )
    ok("web driver: a JavaScript error is on the screen", (wf[4].screen or ""):find("notDefined", 1, true))
    ok("web driver: a target that is not there is the step's error", wf[5].error ~= nil)
    ok("web driver: a screenshot per step", wf[2].image and vim.uv.fs_stat(wf[2].image) ~= nil)
  else
    eq("web driver: runs", wres[3], nil)
  end
else
  skipped[#skipped + 1] = "web driver (no node/Playwright/python3/curl)"
end

-- ── the use phase in a build (fake model, the real CLI driver) ───────────────

package.loaded["agent.selection"] = {
  current = function()
    return { backend = "fake", model = "m" }
  end,
  label = function()
    return "fake/m"
  end,
}
package.loaded["utils.modal"] = {
  hl = setmetatable({}, {
    __index = function(_, k)
      return k
    end,
  }),
  confirm = function(_, _, yes)
    yes()
  end,
}
local uroot = project("useflow", {
  ["AGENTS.md"] = "# A\n",
  ["STACK.md"] = "# S\n",
  ["DESIGN.md"] = "# D\n",
  ["SPEC.md"] = "# P\nFR-1: `calc 2 3` prints 5\n",
})
vim.system({ "git", "init", "-q" }, { cwd = uroot }):wait()
local use_mod = require "agent.kit.build.use"
local saved_ready = use_mod.ready
use_mod.ready = function(r)
  return { root = r, launch = { kind = "cli", argv = { "sh", r .. "/calc.sh" }, what = "test CLI" } }
end
local bverify_checks = bverify.checks
bverify.checks = function()
  return { {
    label = "fake check",
    fn = function()
      return true, ""
    end,
  } }
end
local asked, seen = {}, {}
package.loaded["agent"] = {
  complete = function(r, cb)
    asked[#asked + 1] = r.action
    local answers = {
      kit_build_plan = vim.json.encode {
        name = "calc",
        wiring = { { req = "FR-1", action = "runs calc 2 3", code = "calc.sh adds", shows = "prints 5" } },
        files = { { path = "calc.sh", purpose = "adds two numbers", exports = {} } },
      },
      kit_build_file = "Here is the file:\n```sh\necho $(( $1 - $2 ))\n```",
      kit_build_scenarios = '{"scenarios":[{"name":"adds","covers":["FR-1"],"steps":[{"do":"run","args":["2","3"],"see":["5"],"expect":"5"}]}]}',
      kit_build_fix = "echo $(( $1 + $2 ))",
    }
    local text = answers[r.action]
    if r.action == "kit_build_scenarios" and not seen.scenarios then -- invalid JSON first (a stray brace): asked again
      seen.scenarios = true
      text = '{"scenarios":[{"name":"adds","steps":[{"do":"run","args":["2","3"]}}, "see":["5"]}]}'
    end
    if r.action == "kit_build_use" then
      seen.verdicts = (seen.verdicts or 0) + 1
      seen.prompt = seen.prompt or r.prompt -- the first verdict: the one with the failure
      text = seen.verdicts == 1
          and '{"verdict":"fail","issues":[{"scenario":1,"step":1,"severity":"blocker","problem":"prints -1"}],"diagnosis":"it subtracts","files":[{"path":"calc.sh","change":"add"}]}'
        or '{"verdict":"pass","issues":[],"diagnosis":"","files":[]}'
    end
    cb(true, text or "", { tokens_in = 10, tokens_out = 2 })
    return { kill = function() end }
  end,
}
local build = require "agent.kit.build"
local bstate = require "agent.kit.build.state"
vim.cmd.edit(vim.fn.fnameescape(uroot .. "/AGENTS.md"))
build.open()
build.go()
vim.wait(1600)
build.go()
vim.wait(15000, function()
  return bstate.run.phase == "done" or bstate.run.phase == "failed"
end)
eq(
  "use flow: the file was cleaned before it was written",
  read(uroot .. "/calc.sh") ~= nil and not read(uroot .. "/calc.sh"):find "Here is",
  true
)
eq(
  "use flow: scenarios (invalid JSON asked again once), a verdict, the fix, the same scenarios again, a passing verdict",
  vim.tbl_filter(function(a)
    return a ~= "kit_build_plan" and a ~= "kit_build_file"
  end, asked),
  { "kit_build_scenarios", "kit_build_scenarios", "kit_build_use", "kit_build_fix", "kit_build_use" }
)
ok(
  "use flow: the judge saw the failed free check",
  seen.prompt and seen.prompt:find('checks FAILED: "5" is not on the screen', 1, true)
)
eq("use flow: the fixed file", read(uroot .. "/calc.sh"), "echo $(( $1 + $2 ))\n")
eq(
  "use flow: done, the user gets it",
  { bstate.run.phase, bstate.run.use.passed, bstate.run.use.total, bstate.run.use.plays },
  { "done", 1, 1, 2 }
)
ok("use flow: the outcome says it", bstate.run.outcome:find("used 1/1", 1, true))
ok("use flow: frames kept for you", vim.uv.fs_stat(bstate.run.use.dir .. "/frames.json") ~= nil)
build.recheck()
vim.wait(3000, function()
  return not bstate.run.running
end)
eq("use flow: a recheck does not use the app again (0 tokens)", #vim.tbl_filter(function(a)
  return a == "kit_build_use"
end, asked), 2)
use_mod.ready, bverify.checks = saved_ready, bverify_checks
vim.cmd "silent! tabonly"

vim.fn.delete(base, "rf")
for _, s in ipairs(skipped) do
  print("skipped: " .. s)
end
print(("%d/%d passed"):format(total - fails, total))
if fails == 0 then
  print "ALL OK"
else
  print(("FAILURES: %d"):format(fails))
end
vim.cmd "qa!"
