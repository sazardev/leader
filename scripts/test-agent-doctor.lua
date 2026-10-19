-- Tests of the troubleshooting agent (agent/doctor): the evidence (colors, repeats, secrets, cut, stack frames), the free
-- checks of a project and of the toolchain, the read-only tools the model may use (allowlist, secrets never readable), the
-- request and the strict reading of the answer, the screen's rows and panes, and the whole flow with a fake model: free
-- findings first, one confirmed request, a round of "let me look at this file", steps run captured / as an edit proposal,
-- and "check again". No network, no tokens.
local ROOT = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
local K = dofile(ROOT .. "/scripts/agent-kit.lua")
local eq, ok = K.eq, K.ok

local evidence = require "agent.doctor.evidence"
local probe = require "agent.doctor.probe"
local tools = require "agent.doctor.tools"
local prompt = require "agent.doctor.prompt"
local steps = require "agent.doctor.steps"
local ui = require "agent.doctor.ui"

-- ── evidence ────────────────────────────────────────────────────────────────
eq("clean: colors and carriage returns go", evidence.clean "\27[31mboom\27[0m\r\nnext", "boom\nnext")
eq(
  "clean: repeated lines fold into a count",
  evidence.clean "a\nretry\nretry\nretry\nz",
  "a\nretry\n[… the line above repeated 2 more times]\nz"
)
local red = evidence.redact
ok("redact: an assignment", red("DB_PASSWORD=hunter2"):find("hunter2", 1, true) == nil and red("DB_PASSWORD=hunter2"):find("DB_PASSWORD", 1, true) ~= nil)
ok("redact: a json key", red('{"api_key": "zzz999"}'):find("zzz999", 1, true) == nil)
ok("redact: a token", red("token: abc.def"):find("abc.def", 1, true) == nil)
ok("redact: a connection string keeps the host", red("postgres://app:s3cr3t@db:5432/x"):find("s3cr3t", 1, true) == nil and red("postgres://app:s3cr3t@db:5432/x"):find("@db:5432", 1, true) ~= nil)
ok("redact: a bearer token", red("Authorization: Bearer eyJ0eXAi.abc"):find("eyJ0eXAi", 1, true) == nil)
ok("redact: an AWS key", red("key AKIAABCDEFGHIJKLMNOP end"):find("AKIA", 1, true) == nil)
ok("redact: a private key block", red("-----BEGIN RSA PRIVATE KEY-----\nMIIE\n-----END RSA PRIVATE KEY-----"):find("MIIE", 1, true) == nil)
eq("redact: plain text is untouched", red "listening on port 3000", "listening on port 3000")

local noise = {}
for i = 1, 400 do
  noise[#noise + 1] = ("compiling module %d with some words to take room"):format(i)
end
table.insert(noise, 120, "error: cannot find package \"github.com/x/y\"")
noise[#noise + 1] = "FAIL build failed"
local big = table.concat(noise, "\n")
local cut = evidence.excerpt(big, 2500)
ok("excerpt: fits the budget", #cut <= 2600)
ok("excerpt: keeps the first error", cut:find("cannot find package", 1, true) ~= nil)
ok("excerpt: keeps the end", cut:find("FAIL build failed", 1, true) ~= nil)
ok("excerpt: says what it cut", cut:find("lines omitted", 1, true) ~= nil)
eq("excerpt: a short text is untouched", evidence.excerpt("short", 100), "short")

local exists = {
  ["/p/src/app.ts"] = true,
  ["/p/main.go"] = true,
  ["/p/app.py"] = true,
}
local function ex(abs)
  return exists[abs] == true
end
local frames = evidence.frames("at run (src/app.ts:12:5)\nat /p/node_modules/x/index.js:3:1\nat nothing (src/gone.ts:1:1)\n\tmain.go:40 +0x1d", "/p", ex, 6)
eq("frames: project files only, in order", vim.tbl_map(function(f) return f.file:sub(4) .. ":" .. f.lnum end, frames), { "src/app.ts:12", "main.go:40" })
local py = evidence.frames('Traceback (most recent call last):\n  File "/p/app.py", line 3, in <module>\n    main()\n  File "/p/app.py", line 9, in main\n    boom()', "/p", ex, 6)
eq("frames: a Python traceback puts the culprit first", { py[1].lnum, py[2].lnum }, { 9, 3 })
local tmp = vim.fn.tempname()
vim.fn.writefile({ "one", "two", "three", "four", "five" }, tmp)
eq("code_around: numbered, a marker on the line", evidence.code_around(tmp, 3, 1), "    2  two\n>   3  three\n    4  four")

-- ── free checks ─────────────────────────────────────────────────────────────
local function fake_ctx(files, mtimes)
  return {
    root = "/p",
    has = function(rel)
      return files[rel] ~= nil
    end,
    read = function(rel)
      return files[rel]
    end,
    mtime = function(rel)
      return (mtimes or {})[rel]
    end,
  }
end
local c1 = probe.checks(fake_ctx { ["package.json"] = "{}", ["pnpm-lock.yaml"] = "" })
eq("checks: dependencies not installed, with the project's package manager", { c1[1].id, c1[1].steps[1].run }, { "deps-not-installed", "pnpm install" })
local c2 = probe.checks(fake_ctx({ ["package.json"] = "{}", ["package-lock.json"] = "", node_modules = "" }, { ["package.json"] = 200, ["package-lock.json"] = 100 }))
eq("checks: a lockfile older than the manifest", c2[1].id, "lockfile-older")
eq("checks: nothing wrong, nothing said", #probe.checks(fake_ctx({ ["package.json"] = "{}", ["package-lock.json"] = "", node_modules = "" }, { ["package.json"] = 100, ["package-lock.json"] = 200 })), 0)
local c3 = probe.checks(fake_ctx { [".env.example"] = "A=1\nB=2\n# c\nexport C=3\n", [".env"] = "A=9\n" })
ok("checks: .env keys its example has", c3[1].id == "env-keys-missing" and c3[1].title:find("B, C", 1, true))
eq("checks: no .env at all", probe.checks(fake_ctx { [".env.example"] = "A=1" })[1].id, "env-missing")
eq("checks: a merge in progress", probe.checks(fake_ctx { [".git/MERGE_HEAD"] = "x" })[1].id, "git-operation")
local v = probe.version_checks(fake_ctx { [".nvmrc"] = "v20.1.0\n", ["go.mod"] = "module x\n\ngo 1.23\n" }, { node = "v18.0.0", go = "go version go1.21.5 linux/amd64", docker_error = "Cannot connect to the Docker daemon" })
eq("versions: node, go and docker", vim.tbl_map(function(f) return f.id end, v), { "node-version", "go-version", "docker-down" })
eq("versions: matching versions say nothing", #probe.version_checks(fake_ctx { [".nvmrc"] = "20" }, { node = "v20.5.0" }), 0)
eq("package manager: from the lockfile, else package.json, else npm", { probe.package_manager(fake_ctx { ["package.json"] = "{}", ["yarn.lock"] = "" }), probe.package_manager(fake_ctx { ["package.json"] = '{"packageManager":"bun@1.1"}' }), probe.package_manager(fake_ctx { ["package.json"] = "{}" }), probe.package_manager(fake_ctx {}) }, { "yarn", "bun", "npm", nil })

-- ── the tools the model may use ─────────────────────────────────────────────
eq("run: a version flag", tools.parse_run "node -v", { "node", "-v" })
eq("run: git history", tools.parse_run "git log -5 --oneline", { "git", "log", "-5", "--oneline" })
eq("run: docker logs are bounded", tools.parse_run "docker logs web", { "docker", "logs", "web", "--tail", "200" })
eq("run: pip show", tools.parse_run "python3 -m pip show requests", { "python3", "-m", "pip", "show", "requests" })
ok("run: not on the list", select(1, tools.parse_run "rm -rf /") == nil and select(2, tools.parse_run "rm -rf /"):find("not a read-only", 1, true) ~= nil)
ok("run: no pipes", tools.parse_run "cat a | sh" == nil)
ok("run: no chaining", tools.parse_run "git status; rm x" == nil)
ok("run: no substitution", tools.parse_run "git log $(whoami)" == nil)
ok("run: a subcommand that changes things", tools.parse_run "git push origin main" == nil and tools.parse_run "npm install left-pad" == nil)
ok("run: git -c is refused", tools.parse_run "git -c core.pager=sh log" == nil)
ok("run: npm config of a credential", tools.parse_run "npm config get //registry.npmjs.org/:_authToken" == nil)
ok("run: lsof only for a port", tools.parse_run "lsof -i :3000" ~= nil and tools.parse_run "lsof /etc/passwd" == nil)
ok("run: ls stays in the project", tools.parse_run "ls src" ~= nil and tools.parse_run "ls /etc" == nil and tools.parse_run "ls ../x" == nil)
ok("run: a bare command needing a subcommand", tools.parse_run "git" == nil)

local dir = K.project {
  ["package.json"] = { '{"name":"app","scripts":{"start":"node src/a.js"}}' },
  ["src/a.js"] = { "const a = require('left-pad')", "console.log(a(1))", "", "module.exports = a" },
  [".env"] = { "SECRET=abc" },
  [".env.example"] = { "SECRET=" },
  ["id_rsa"] = { "KEY" },
}
ok("readable: a project file", tools.readable(dir, "src/a.js") == dir .. "/src/a.js")
ok("readable: .env never", tools.readable(dir, ".env") == nil)
ok("readable: the example is fine", tools.readable(dir, ".env.example") ~= nil)
ok("readable: keys and ssh never", tools.readable(dir, "id_rsa") == nil and tools.readable(dir, ".ssh/config") == nil)
ok("readable: outside the project never", tools.readable(dir, "../etc/passwd") == nil and tools.readable(dir, "/etc/passwd") == nil)
local function call(c)
  local out
  tools.call(c, dir, function(t)
    out = t
  end)
  K.wait(function()
    return out ~= nil
  end, 4000)
  return out
end
ok("read: numbered lines of the file", call({ tool = "read", path = "src/a.js", from = 1, to = 2 }):find("2  console.log(a(1))", 1, true) ~= nil)
ok("read: a secret is refused as a result the model can read", call({ tool = "read", path = ".env" }):find("^refused:") ~= nil)
ok("list: hides secrets and .git", (function()
  local t = call { tool = "list", path = "." }
  return t:find("src/", 1, true) and not t:find(".env\n", 1, true) and not t:find("id_rsa", 1, true) and not t:find(".git/", 1, true)
end)())
ok("run: runs an allowed command and returns its output", call({ tool = "run", cmd = "git status --short" }):find("^%$ git status") ~= nil)
ok("run: a refusal is a result", call({ tool = "run", cmd = "rm -rf x" }):find("^refused:") ~= nil)
ok("unknown tool", call({ tool = "shell" }):find("^refused: unknown tool") ~= nil)
if vim.fn.executable "rg" == 1 then
  ok("search: finds a string, never in .env", call({ tool = "search", pattern = "left-pad" }):find("src/a.js:1", 1, true) ~= nil and call({ tool = "search", pattern = "abc" }):find("no match", 1, true) ~= nil)
end

-- ── the request and the answer ──────────────────────────────────────────────
local req = prompt.request({
  problem = "it crashes",
  source = "the last terminal",
  output = "boom",
  code = { { path = "src/a.js", lnum = 2, text = ">   2  x" } },
  versions = { node = "v20.1.0", go_missing = "" },
  changes = "git status:\n M a",
  known = { { id = "x", title = "A thing", cause = "because", steps = { { kind = "command", title = "Do", run = "npm i" } } } },
  tried = { "ran `npm i` → exit 1" },
  tool_results = { { call = "read a.js", text = "lines" } },
  question = "and now?",
}, "TOOLS")
ok("request: every piece in its tag", (function()
  for _, tag in ipairs { "environment", "changes", "source", "code", "output", "known", "tried", "tool_results", "problem", "question" } do
    if not req.prompt:find("<" .. tag .. ">", 1, true) then
      return false
    end
  end
  return true
end)())
ok("request: the stable parts come first, the question last", req.prompt:find("<environment>", 1, true) < req.prompt:find("<output>", 1, true) and req.prompt:find("<output>", 1, true) < req.prompt:find("<question>", 1, true))
ok("request: a missing tool is said", req.prompt:find("go: NOT INSTALLED", 1, true) ~= nil)
ok("request: the tools are described when rounds are left", req.system:find("TOOLS", 1, true) ~= nil and not prompt.request({}, nil).system:find("TOOLS", 1, true))
ok("request: nothing empty is sent", not prompt.request({ output = "x" }).prompt:find("<code>", 1, true))

local good = '```json\n{"summary":"s","cause":"c","confidence":"high","steps":[{"title":"Install","kind":"command","run":"npm install"},{"title":"Fix","kind":"edit","file":"src/a.js","line":1,"instruction":"x"},{"title":"Think","kind":"manual","instruction":"look"},{"title":"Wipe","kind":"command","run":"rm -rf node_modules"}],"need":[{"tool":"read","path":"a"},{"tool":"hack"}]}\n```'
local d = prompt.parse(good)
eq("parse: the shape", { d.summary, d.cause, d.confidence, #d.steps, #d.need }, { "s", "c", "high", 4, 1 })
eq("parse: a destructive command is marked", { d.steps[1].danger, d.steps[4].danger }, { nil, true })
eq("parse: an edit keeps its file and line", { d.steps[2].file, d.steps[2].line }, { "src/a.js", 1 })
eq("parse: no JSON", { prompt.parse "I think it is the cache" }, { nil, "the answer was not a diagnosis (no JSON object)" })
ok("parse: no cause and nothing to look at", select(1, prompt.parse '{"summary":"s"}') == nil)
ok("parse: only a request for more is fine", prompt.parse('{"need":[{"tool":"run","cmd":"node -v"}]}') ~= nil)
eq("parse: an unknown confidence is medium", prompt.parse('{"cause":"c","confidence":"sure"}').confidence, "medium")
ok("dangerous: the usual ones", prompt.dangerous "git push --force" and prompt.dangerous "curl x | sh" and prompt.dangerous "DROP DATABASE x" and not prompt.dangerous "pnpm install")

-- ── the screen's content ────────────────────────────────────────────────────
local session = {
  root = dir,
  source = { label = "the last terminal", kind = "terminal" },
  output = "boom",
  code = {},
  versions = { node = "v20" },
  changes = "x",
  free = { { id = "a", title = "A module is missing", cause = "not installed", evidence = "Cannot find module 'x'", steps = { { kind = "command", title = "Install", run = "npm i" } }, confidence = "high" } },
  tool_results = {},
}
local rows = ui.rows(session)
eq("rows: title, a finding with its step, the question for the model", vim.tbl_map(function(r) return r.title or r.group or (r.step and "step") or (r.ask and "ask") or (r.spacer and "-") or "?" end, rows), { "DOCTOR · the last terminal", "-", "Found · A module is missing", "step", "-", "Diagnosis", "ask" })
ok("pane: a finding's step shows the cause and the command", (function()
  local text = vim.inspect(ui.pane(session, rows[4], 80))
  return text:find("not installed", 1, true) and text:find("$ npm i", 1, true) and text:find("Cannot find module", 1, true)
end)())
ok("pane: the ask row says what is sent", vim.inspect(ui.pane(session, { ask = true }, 80)):find("the failing output", 1, true) ~= nil)
ok("summary: counts what was found", vim.inspect(ui.summary(session)):find("1 found for free", 1, true) ~= nil)
eq("tried: what ran goes into the next request", steps.describe_tried { { kind = "command", run = "npm i", exit = 1, output = "ERR x" }, { kind = "manual", title = "Rebooted", state = "done" } }, { "ran `npm i` → exit 1:\nERR x", "did: Rebooted" })

-- ── the whole flow with a fake model ────────────────────────────────────────
local FAKE = K.fake()
local settings = require("core.settings").agent
settings.verify.enabled = false
local doctor = require "agent.doctor"
local market = require "utils.market"
local replace = require "agent.output.replace"

local function press(buf, key)
  local lhs = vim.api.nvim_replace_termcodes(key, true, true, true)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if vim.api.nvim_replace_termcodes(map.lhs, true, true, true) == lhs then
      return map.callback()
    end
  end
  error("no mapping " .. key)
end
local function text_of(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end
local function cursor_on(m, pred)
  for i, r in ipairs(m.rows) do
    if pred(r) then
      vim.api.nvim_win_set_cursor(m.wins.list, { i, 0 })
      market.refresh(m)
      return true
    end
  end
  return false
end

vim.o.columns, vim.o.lines = 140, 40
vim.cmd.edit(vim.fn.fnameescape(dir .. "/src/a.js"))
local output = "Error: Cannot find module 'left-pad'\n    at Object.<anonymous> (src/a.js:1:11)\nDB_PASSWORD=hunter2"
doctor.start { root = dir, source = { label = "the last terminal", kind = "terminal", text = output }, rerun = "true" }
K.wait(function()
  local c = doctor.case(dir)
  return c ~= nil and c.market ~= nil and vim.api.nvim_win_is_valid(c.market.wins.list)
end, 8000)
local case = doctor.case(dir)
local m = case.market
ok("flow: the screen opens by itself with the free findings", text_of(m.bufs.list):upper():find("NODE MODULE IS MISSING", 1, true) ~= nil)
ok("flow: the code the stack points into is attached", #case.code == 1 and case.code[1].path == "src/a.js")
ok("flow: the secret in the output is gone before anything is sent", not case.output:find("hunter2", 1, true))
eq("flow: nothing was sent to a model yet", FAKE.calls, 0)

-- ask: round 1 wants to read two files, round 2 concludes
FAKE.answer = "yes"
FAKE.text = function(r)
  if r.prompt:find("<tool_results>", 1, true) then
    return vim.json.encode {
      summary = "left-pad is not installed",
      cause = "src/a.js requires left-pad but node_modules has no such package.",
      confidence = "high",
      steps = {
        { title = "Say hi", kind = "command", run = "echo hi" },
        { title = "Use String.padStart", kind = "edit", file = "src/a.js", line = 1, instruction = "drop left-pad" },
        { title = "Restart the server", kind = "manual", instruction = "then reload" },
      },
    }
  end
  return vim.json.encode { need = { { tool = "read", path = "src/a.js", from = 1, to = 4 }, { tool = "read", path = ".env" } } }
end
cursor_on(m, function(r)
  return r.ask
end)
press(m.bufs.list, "<CR>")
K.wait(function()
  return case.diagnosis ~= nil
end, 10000)
eq("flow: two requests, the second after looking at what it asked", FAKE.calls, 2)
ok("flow: the confirmation said what is sent", vim.iter(FAKE.asked):any(function(a)
  return a.title == "Diagnose"
end))
ok("flow: the first request offered the tools", FAKE.reqs[1].system:find("need", 1, true) ~= nil)
ok("flow: the second carries what it looked at", FAKE.reqs[2].prompt:find("<tool_results>", 1, true) and FAKE.reqs[2].prompt:find("const a = require", 1, true))
ok("flow: and the refusal for the secret file", FAKE.reqs[2].prompt:find("refused:", 1, true) ~= nil)
ok("flow: no secret ever went out", not FAKE.reqs[1].prompt:find("hunter2", 1, true) and not FAKE.reqs[2].prompt:find("hunter2", 1, true))
eq("flow: the diagnosis is on the screen", case.diagnosis.summary, "left-pad is not installed")
ok("flow: its steps are rows", text_of(m.bufs.list):find("Say hi", 1, true) and text_of(m.bufs.list):find("Use String.padStart", 1, true))
eq("flow: the case is not asking anymore", case.asking, nil)

-- a command step: asked first, run captured, the result comes back
cursor_on(m, function(r)
  return r.step and r.step.title == "Say hi"
end)
press(m.bufs.list, "<CR>")
K.wait(function()
  return case.diagnosis.steps[1].state == "done"
end, 6000)
eq("step: the command ran and passed", { case.diagnosis.steps[1].state, case.diagnosis.steps[1].exit }, { "done", 0 })
ok("step: its output is in the pane", (function()
  cursor_on(m, function(r)
    return r.step and r.step.title == "Say hi"
  end)
  return text_of(m.bufs.pane):find("hi", 1, true) ~= nil and text_of(m.bufs.pane):find("exit 0", 1, true) ~= nil
end)())
ok("step: and in what the next request calls tried", steps.describe_tried(case.diagnosis.steps)[1]:find("ran `echo hi` → exit 0", 1, true) ~= nil)
ok("step: it asked before running", vim.iter(FAKE.asked):any(function(a)
  return a.title == "Say hi"
end))

-- a manual step is marked by hand
cursor_on(m, function(r)
  return r.step and r.step.title == "Restart the server"
end)
press(m.bufs.list, "<Space>")
eq("step: Space marks a manual step done", case.diagnosis.steps[3].state, "done")

-- an edit step becomes one proposal; accepting it marks the step done
FAKE.text = "```js\nconst a = (n) => String(n).padStart(2)\nconsole.log(a(1))\n\nmodule.exports = a\n```"
cursor_on(m, function(r)
  return r.step and r.step.kind == "edit"
end)
press(m.bufs.list, "<CR>")
K.wait(function()
  return #replace.pending() > 0
end, 8000)
K.idle()
ok("edit: the screen gave way to the code", not vim.api.nvim_win_is_valid(m.wins.list))
eq("edit: one proposal waits", #replace.pending(), 1)
ok("edit: the request carries the diagnosis", FAKE.req.prompt:find("<diagnosis>", 1, true) and FAKE.req.prompt:find("drop left-pad", 1, true))
replace.accept()
eq("edit: accepting marks the step done", case.diagnosis.steps[2].state, "done")
ok("edit: the file has the new code", table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("padStart", 1, true) ~= nil)

-- check again: the command passes now
doctor.reopen()
m = case.market
FAKE.notes = {}
doctor.verify(case)
K.wait(function()
  return case.solved == true
end, 6000)
ok("verify: it runs again and it is fine now", case.solved == true)
ok("verify: and says so", K.note(FAKE):find("nothing failed", 1, true) ~= nil)

-- a refused edit outside the project
local outside = { title = "x", kind = "edit", file = "../../etc/hosts", instruction = "y" }
FAKE.notes = {}
steps.apply_edit(dir, outside, case.diagnosis)
ok("edit: a file outside the project is not touched", K.note(FAKE):find("outside the project", 1, true) ~= nil)

-- an answer that is not a diagnosis is reported, not hidden
local c2 = { root = dir, source = { label = "x", kind = "paste" }, output = "boom", code = {}, versions = {}, free = {}, tool_results = {}, tried = {} }
FAKE.text = "I would try turning it off and on again"
FAKE.notes = {}
doctor.ask(c2)
K.wait(function()
  return FAKE.notes[#FAKE.notes] ~= nil and c2.asking == nil
end, 6000)
ok("answer: not a diagnosis is said so", K.note(FAKE):find("not a diagnosis", 1, true) ~= nil)
eq("answer: and nothing is left half done", c2.diagnosis, nil)

K.finish()
