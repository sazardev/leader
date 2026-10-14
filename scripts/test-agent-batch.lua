-- Tests of refine (Tab on a proposal, Tab on an answer), the batch with its queue, fix all, and the errors parser. Hermetic:
-- a fake model, a temporary Go project, no network or tokens.
local ROOT = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
local K = dofile(ROOT .. "/scripts/agent-kit.lua")
local eq, ok = K.eq, K.ok
local settings = require("core.settings").agent

local dir = K.project {
  ["go.mod"] = { "module example.com/p", "", "go 1.21" },
  ["store.go"] = {
    "package p", -- 1
    "", -- 2
    "func Alpha(a int) int {", -- 3
    "\treturn a + undefinedA", -- 4
    "}", -- 5
    "", -- 6
    "func Beta(b int) int {", -- 7
    "\tx := b", -- 8
    "\treturn b + undefinedB", -- 9
    "}", -- 10
    "", -- 11
    "func Gamma(c int) int {", -- 12
    "\treturn c", -- 13
    "}", -- 14
  },
  ["other.go"] = { "package p", "", "func Delta() int {", "\treturn undefinedD", "}" },
}
local FAKE = K.fake()
local replace = require "agent.output.replace"
local pipeline = require "agent.pipeline"
local events = require "agent.events"
local jobs = require "agent.jobs"

local buf = K.open "store.go"
local NS = vim.api.nvim_create_namespace "test-lsp"
local function diag(line, msg, sev)
  return { lnum = line - 1, col = 0, severity = sev or vim.diagnostic.severity.ERROR, message = msg, source = "gopls" }
end
local function fence(body)
  return "```go\n" .. body .. "\n```"
end
settings.verify.enabled = false -- these suites are about the flows themselves

-- ── refine: a proposal → a new one that starts from it ──────────────────────
vim.diagnostic.set(NS, buf, { diag(4, "undefined: undefinedA") })
K.at(4)
FAKE.text = function(req)
  if req.prompt:find("<previous_proposal>", 1, true) then
    return fence "func Alpha(a int) int {\n\treturn a * 2\n}"
  end
  return fence "func Alpha(a int) int {\n\treturn a + 1\n}"
end
pipeline.run "fix_block"
K.idle()
local first = replace.pending()[1]
ok("refine: the first proposal is waiting", first ~= nil)
eq("refine: and the hint offers the key", (require("agent.refine").key_label()), "Tab")
FAKE.input = "double it instead"
replace.refine()
K.idle()
local pending = replace.pending()
eq(
  "refine: its field cannot be skipped (an empty refinement asks for nothing)",
  FAKE.asked,
  { skippable = false, field = "how should it change?" }
)
eq("refine: the old proposal gave way to one new one", #pending, 1)
ok("refine: it is a different job", pending[1] and pending[1].job.id ~= first.job.id)
ok(
  "refine: the prompt carries the previous proposal",
  FAKE.req.prompt:find("<previous_proposal>", 1, true) ~= nil and FAKE.req.prompt:find("return a + 1", 1, true) ~= nil
)
ok("refine: and the user's instruction", FAKE.req.prompt:find("double it instead", 1, true) ~= nil)
ok("refine: the new code is the refined one", table.concat(pending[1].lines, "\n"):find("a * 2", 1, true) ~= nil)
eq("refine: the lineage is kept", pending[1].job.meta.refine, 1)
eq("refine: the batch hint does not stick to a refined proposal", pending[1].job.meta.hint, nil)
eq("refine: the buffer was never touched", vim.api.nvim_buf_get_lines(buf, 3, 4, false)[1], "\treturn a + undefinedA")
local dropped = {}
events.on("proposal.dropped", function(ev)
  dropped[#dropped + 1] = ev.how
end)
replace.accept()
eq("refine: accepting writes the refined code", vim.api.nvim_buf_get_lines(buf, 3, 4, false)[1], "\treturn a * 2")

-- ── follow-up of an answer ──────────────────────────────────────────────────
FAKE.input = "why is that a problem?"
K.at(12)
FAKE.text = "It is fine: it returns the argument."
require("agent.pipeline").run "explain"
K.idle()
local ex = jobs.last()
FAKE.calls = 0
FAKE.input = "and what if c is negative?"
FAKE.text = function()
  return "Nothing changes."
end
require("agent.refine").answer(ex, "It is fine: it returns the argument.")
K.idle()
eq("follow-up: one request", FAKE.calls, 1)
ok(
  "follow-up: the earlier answer is in the prompt as conversation",
  FAKE.req.prompt:find("<conversation>", 1, true) ~= nil
    and FAKE.req.prompt:find("returns the argument", 1, true) ~= nil
)
ok("follow-up: with the new question", FAKE.req.prompt:find("c is negative", 1, true) ~= nil)
local thread = require("agent.refine").render_thread {
  { q = "one", a = string.rep("x", 3000) },
  { q = "two", a = string.rep("y", 3000) },
}
ok(
  "follow-up: a long conversation drops its oldest turn",
  not thread:find("Q: one", 1, true) and thread:find("Q: two", 1, true) ~= nil
)

-- ── fix all: grouped by function, asked once, run in a row ──────────────────
replace.discard_all()
vim.diagnostic.set(NS, buf, {
  diag(4, "undefined: undefinedA"),
  diag(8, "declared and not used: x"),
  diag(9, "undefined: undefinedB"),
  diag(13, "just a hint", vim.diagnostic.severity.HINT),
})
local group = require "agent.fixall.group"
local groups = group.by_scope(
  group.at_least(vim.diagnostic.get(buf), group.severity_number "warn"),
  require("agent.fixall").resolver(buf)
)
eq("group: findings in one function are one group", #groups, 2)
eq("group: bottom of the file first", { groups[1].name, groups[2].name }, { "Beta", "Alpha" })
eq("group: Beta holds both of its problems", #groups[1].diags, 2)
eq(
  "group: loose lines next to each other merge",
  #group.by_scope({ diag(30, "a"), diag(31, "b"), diag(60, "c") }, function()
    return nil
  end),
  2
)
eq(
  "group: severity filter keeps errors and warnings",
  #group.at_least(vim.diagnostic.get(buf), group.severity_number "warn"),
  3
)

FAKE.calls, FAKE.asked = 0, {}
FAKE.text = function(req)
  local name = req.prompt:match 'name="(%w+)"'
  return fence(("func %s(a int) int {\n\treturn 1\n}"):format(name or "X"))
end
FAKE.input = nil
require("agent.fixall").run()
eq("fix all: it asked ONCE, with the total", { #FAKE.asked, FAKE.asked[1] and FAKE.asked[1].title }, { 1, "fix all" })
ok(
  "fix all: the question names the pieces",
  vim.inspect(FAKE.asked[1].lines):find("Beta", 1, true) ~= nil
    and vim.inspect(FAKE.asked[1].lines):find("2 problems", 1, true) ~= nil
)
K.idle()
K.wait(function()
  return #replace.pending() >= 2
end, 6000)
eq("fix all: two requests (one per function), not three", FAKE.calls, 2)
eq("fix all: two proposals waiting", #replace.pending(), 2)
local labels = vim.tbl_map(function(p)
  return p.job.action.label
end, replace.pending())
eq("fix all: each shows its progress in the statusline label", labels, { "fix all 1/2", "fix all 2/2" })
ok("fix all: the hint tells how to move", replace.pending()[1].job.meta.hint:find("next", 1, true) ~= nil)
eq("fix all: no budget question per piece (the batch asked once)", #FAKE.asked, 1)

-- the queue
local queue = require "agent.batch.queue"
vim.api.nvim_win_set_cursor(0, { 1, 0 })
queue.step(1)
eq("queue: ] goes to the first proposal", vim.api.nvim_win_get_cursor(0)[1], 7) -- Beta, the first the batch produced
queue.step(1)
eq("queue: ] again goes to the next", vim.api.nvim_win_get_cursor(0)[1], 3)
queue.step(1)
eq("queue: and wraps around", vim.api.nvim_win_get_cursor(0)[1], 7)
queue.step(-1)
eq("queue: [ goes back", vim.api.nvim_win_get_cursor(0)[1], 3)
queue.list()
eq("queue: the quickfix lists them", #vim.fn.getqflist(), 2)
vim.cmd "cclose"
FAKE.answer = "no"
queue.accept_all()
eq("queue: accept all asks first, and no leaves them", #replace.pending(), 2)
FAKE.answer = "yes"
queue.accept_all()
eq("queue: yes accepts every one", #replace.pending(), 0)
eq("queue: the code changed", vim.api.nvim_buf_get_lines(buf, 7, 9, false), { "\treturn 1", "}" })
vim.cmd "silent! %bwipeout!"

-- a batch stops when a piece is denied or cancelled
buf = K.open "store.go"
vim.diagnostic.set(NS, buf, { diag(4, "undefined: undefinedA"), diag(9, "undefined: undefinedB") })
settings.budget.day_usd = 0.00001
FAKE.calls = 0
require("agent.fixall").run()
K.wait(function()
  return #require("agent.batch").active() == 0
end, 4000)
eq("batch: a blocked piece stops the rest", FAKE.calls, 0)
settings.budget.day_usd = nil

-- ── errors parser: sources and grouping ─────────────────────────────────────
local parse = require "agent.errors.parse"
local errs = parse.parse(
  "# example.com/p\n./store.go:4:12: undefined: undefinedA\nstore.go:9:12: undefined: undefinedB\nFAIL",
  { root = dir }
)
eq("errors: go output → two errors in the project", #errs, 2)
eq(
  "errors: absolute path, line and message",
  { vim.fn.fnamemodify(errs[1].file, ":t"), errs[1].lnum, errs[1].text },
  { "store.go", 4, "undefined: undefinedA" }
)
eq("errors: files outside the project are ignored", #parse.parse("/etc/hosts:1:1: nope", { root = dir }), 0)
eq(
  "errors: colors in a terminal buffer are stripped",
  #parse.parse("\27[31mstore.go:4:1: boom\27[0m", { root = dir }),
  1
)
eq("errors: an error twice is one", #parse.parse("store.go:4:1: boom\nstore.go:4:1: boom", { root = dir }), 1)

-- ── fix from output: terminal, quickfix and the whole flow ──────────────────
local source = require "agent.errors.source"
vim.cmd "silent! %bwipeout!"
buf = K.open "store.go"
vim.diagnostic.set(NS, buf, {})
vim.cmd "enew"
local term_job = vim.fn.jobstart({
  "sh",
  "-c",
  "printf '\\033[31mstore.go:4:12: undefined: undefinedA\\033[0m\\nstore.go:9:12: undefined: undefinedB\\n'; exit 1",
}, { term = true })
K.wait(function()
  return (source.terminal(50) or ""):find("undefinedB", 1, true) ~= nil
end, 4000)
local text = source.terminal(50) or ""
ok(
  "source: the last terminal's text is read, colors stripped",
  text:find("undefinedA", 1, true) ~= nil and not text:find("\27", 1, true)
)
local found, label = source.auto(dir, { terminal_lines = 50 })
eq("source: auto finds the terminal's errors first", { #found, label }, { 2, "the last terminal" })
vim.fn.jobstop(term_job)
vim.cmd "silent! bwipeout!"

vim.cmd("silent edit " .. dir .. "/store.go")
buf = vim.api.nvim_get_current_buf()
vim.fn.setqflist(
  { { filename = dir .. "/other.go", lnum = 4, col = 9, text = "undefined: undefinedD", type = "E" } },
  "r"
)
local qf_found, qf_label = source.auto(dir, { terminal_lines = 50 })
eq("source: without a terminal it falls back to the quickfix list", { #qf_found, qf_label }, { 1, "the quickfix list" })

-- the whole flow on the quickfix: one piece (Delta in other.go), asked once, the section carries ONLY its error
FAKE.calls, FAKE.asked = 0, {}
FAKE.answer = "yes"
FAKE.text = function(req)
  return fence "func Delta() int {\n\treturn 4\n}"
end
require("agent.errors").run()
eq(
  "errors: one confirmation, naming where the errors came from",
  { #FAKE.asked, FAKE.asked[1] and FAKE.asked[1].title },
  { 1, "fix output" }
)
ok(
  "errors: the question says how many and from where",
  vim.inspect(FAKE.asked[1].lines):find("1 error from the quickfix list", 1, true) ~= nil
)
K.idle()
K.wait(function()
  return #replace.pending() >= 1
end, 6000)
ok(
  "errors: the prompt has a build_errors section with the line and message",
  FAKE.req.prompt:find("<build_errors>", 1, true) ~= nil
    and FAKE.req.prompt:find("4:9 undefined: undefinedD", 1, true) ~= nil
)
ok(
  "errors: and the framing of a tool's errors",
  FAKE.req.system:find("TASK fix the errors a tool printed", 1, true) ~= nil
)
eq("errors: one proposal waiting", #replace.pending(), 1)
replace.discard_all()

-- two terminal errors in two functions → two pieces, each with only its own errors
local pieces = require("agent.errors").items(
  parse.parse("store.go:4:12: undefined: undefinedA\nstore.go:9:12: undefined: undefinedB", { root = dir }),
  "go build"
)
eq(
  "errors: two functions, two pieces",
  { #pieces, pieces[1] and pieces[1].label, pieces[2] and pieces[2].label },
  { 2, "Beta", "Alpha" }
)
ok(
  "errors: each section has just its own error",
  pieces[1].extra[1].text:find("undefinedB", 1, true) ~= nil and not pieces[1].extra[1].text:find("undefinedA", 1, true)
)
eq("errors: and the command it came from", pieces[1].extra[1].text:match "^%$ (.-)\n", "go build")

-- a command typed by the user runs through the shell (a pipeline, `a && b`) and its errors are used
local cmd_out
source.command({
  cmd = {
    vim.o.shell,
    vim.o.shellcmdflag,
    "echo store.go:4:12: undefined: x && echo store.go:9:1: missing return; exit 1",
  },
  cwd = dir,
  label = "x",
}, function(text)
  cmd_out = text
end)
K.wait(function()
  return cmd_out ~= nil
end, 4000)
eq(
  "source: a command through the shell, errors parsed from what it printed",
  #parse.parse(cmd_out or "", { root = dir }),
  2
)

-- ── the build check (pure parts) ────────────────────────────────────────────
local build = require "agent.verify.build"
local go_cmd = build.command_for(dir .. "/store.go", "go", "auto")
eq(
  "build: go projects build with `go build ./...` from the module root",
  { go_cmd.label, go_cmd.cwd },
  { "go build ./...", dir }
)
eq("build: off means nothing", (build.command_for(dir .. "/store.go", "go", false)), nil)
eq(
  "build: a language with no known command is told so",
  select(2, build.command_for("x.zig", "zig", "auto")),
  "no build command known for zig"
)
eq(
  "build: the user's own command wins",
  build.command_for(dir .. "/a.lua", "lua", { lua = { "luacheck", "." } }).label,
  "luacheck ."
)
local errs2 = {
  { file = dir .. "/store.go", lnum = 5, text = "a" },
  { file = dir .. "/store.go", lnum = 40, text = "far" },
  { file = dir .. "/other.go", lnum = 5, text = "elsewhere" },
}
local mine, elsewhere = build.attribute(errs2, dir .. "/store.go", { { first = 3, last = 8 } })
eq("build: only the errors on the accepted code are blamed on it", { #mine, elsewhere }, { 1, 2 })
eq(
  "build: errors a couple of lines off still count",
  #build.attribute(
    { { file = dir .. "/store.go", lnum = 10, text = "x" } },
    dir .. "/store.go",
    { { first = 3, last = 8 } }
  ),
  1
)

K.finish()
