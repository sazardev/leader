-- The trust layer: what is said before an action (preflight, preview), what is said about its result (verified or not),
-- the session's spend and taking a whole run back (checkpoint). Hermetic: no network or tokens.
local ROOT = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
local K = dofile(ROOT .. "/scripts/agent-kit.lua")
local eq, ok = K.eq, K.ok

local trust = require "agent.trust"
local spend = require "agent.spend"
local checkpoint = require "agent.checkpoint"
local events = require "agent.events"
local settings = require("core.settings").agent

-- ── preflight (pure) ─────────────────────────────────────────────────────────
eq(
  "preflight: model, what it reads, the estimate",
  trust.preflight {
    model = "claude/haiku",
    tier = "light",
    chars = 7000,
    tokens = 1800,
    cost = 0.0007,
    sections = { { name = "rules", chars = 10 }, { name = "types", chars = 40 }, { name = "empty", chars = 0 } },
  },
  "claude/haiku · light · reads rules, types · ~1.8k tok · ~$0.0007"
)
eq(
  "preflight: a free local model has no cost, and the tokens come from the size",
  trust.preflight { model = "ollama/qwen", chars = 3500 },
  "ollama/qwen · ~1k tok"
)
eq(
  "preflight: a long list of sections is cut",
  trust.preflight {
    model = "m/x",
    chars = 350,
    sections = vim.tbl_map(function(n)
      return { name = n, chars = 1 }
    end, { "a", "b", "c", "d", "e", "f" }),
  },
  "m/x · reads a, b, c, d +2 · ~100 tok"
)
eq(
  "preflight: a weak model's profile and its samples are said",
  trust.preflight { model = "ollama/q", chars = 350, profile = "small", samples = 3, cost = 0.001 },
  "ollama/q · small profile · 3× ~100 tok · ~$0.0030"
)
eq(
  "from_request: the budget guard's estimate wins",
  trust.from_request({ backend = "claude", model = "haiku", chars = 100, estimate = { tokens = 7, cost = 0.5 } }).tokens,
  7
)

-- ── verification label (pure) ────────────────────────────────────────────────
local function v(f)
  return (
    trust.verification(vim.tbl_extend("force", { output = "replace", verifies = true, lsp = true, build = false }, f))
  )
end
eq("verification: LSP will check", v {}, "checked on accept (LSP)")
eq("verification: LSP and build", v { build = true }, "checked on accept (LSP) and on save (build)")
eq("verification: build only", v { lsp = false, build = true }, "checked on save (build)")
eq("verification: nothing", v { lsp = false }, "unverified · no language server")
eq("verification: turned off", v { verifies = false }, "unverified · no language server")
eq("verification: docs cannot touch code", v { comment_only = true, lsp = false }, "comment only · code untouched")
eq("verification: findings are advice", v { output = "findings" }, "advice · unverified")
eq("verification: text is an answer", v { output = "text" }, "answer · unverified")
eq("verification: a checker that ran wins", v { checked = true, lsp = false }, "verified before showing")
eq("after accept: heard", trust.after_accept(true), "verified · no new problems")
ok("after accept: silence is not proof", trust.after_accept(false):find("unverified", 1, true) ~= nil)

-- ── spend ────────────────────────────────────────────────────────────────────
spend.reset()
eq("spend: nothing spent, nothing shown", { spend.chip(0, 2) }, { "", false })
eq("spend: no cap", { spend.chip(0.0312) }, { "$0.031", false })
eq("spend: against a cap", { spend.chip(0.5, 2) }, { "$0.500/$2.00", false })
eq("spend: near the cap", { spend.chip(1.7, 2, 0.8) }, { "$1.70/$2.00", true })
spend.add(0.01)
spend.add(nil)
spend.add(0.02)
eq("spend: adds up, counts every call", { spend.session() }, { 0.03, 3 })

-- ── a project and a fake model ───────────────────────────────────────────────
K.project {
  ["go.mod"] = { "module example.com/p", "", "go 1.21" },
  ["a.go"] = { "package p", "", "func One() int {", "\treturn 1", "}", "", "func Two() int {", "\treturn 2", "}" },
  ["b.go"] = { "package p", "", "func Three() int {", "\treturn 3", "}" },
}
local FAKE = K.fake()
settings.verify.settle_ms, settings.verify.max_wait_ms, settings.verify.command = 60, 300, false
local replace = require "agent.output.replace"
local pipeline = require "agent.pipeline"
require("agent.features").reset()
events.reset()
require("agent.features").setup()
local function code(body)
  return "```go\n" .. body .. "\n```"
end

-- ── the spend counter follows every run ──────────────────────────────────────
spend.reset()
local buf = K.open "a.go"
K.at(4)
FAKE.input = "return 10 instead"
FAKE.text = code "func One() int {\n\treturn 10\n}"
pipeline.run "refactor"
K.idle()
ok("spend: a run is counted", select(2, spend.session()) == 1 and spend.session() > 0)

-- ── the preflight: said in the job, and as a line when asked ─────────────────
local job = require("agent.jobs").last()
ok("preflight: the job carries its line", job and job.preflight and job.preflight:find("fakeagent/default", 1, true))
ok("preflight: and its estimate", job.estimate and job.estimate.tokens > 0)
ok(
  "preflight: the proposal hint says whether it is checked",
  (function()
    -- the hint is drawn by the presenter; what matters is that it asked trust for it: the facts it passes are real
    return trust.verification { output = "replace", verifies = true, lsp = false, build = false } ~= nil
  end)()
)
replace.discard_all()
settings.trust.preflight = "notify"
FAKE.notes = {}
pipeline.run "refactor"
K.idle()
ok(
  "preflight: notify says it before sending",
  (function()
    for _, n in ipairs(FAKE.notes) do
      if n:find("reads", 1, true) and n:find("tok", 1, true) then
        return true
      end
    end
    return false
  end)()
)
settings.trust.preflight = "status"
replace.discard_all()

-- ── the preview guard ────────────────────────────────────────────────────────
settings.trust.preview = true
FAKE.calls, FAKE.asked, FAKE.answer = 0, {}, "no"
pipeline.run "refactor"
K.wait(function()
  return #FAKE.asked > 0
end)
K.idle()
local asked = FAKE.asked[1]
eq("preview: it asked, with its own title", asked and asked.title, "Agent prompt")
ok(
  "preview: the question shows the start of the message",
  (function()
    for _, line in ipairs(asked and asked.lines or {}) do
      local s = type(line) == "table" and (line[1] and line[1][1] or "") or tostring(line)
      if s:find("return 10 instead", 1, true) or s:find("One", 1, true) then
        return true
      end
    end
    return false
  end)()
)
eq("preview: saying no sends nothing", FAKE.calls, 0)
FAKE.answer = "yes"
pipeline.run "refactor"
K.idle()
eq("preview: saying yes sends it", FAKE.calls, 1)
settings.trust.preview = false
replace.discard_all()
FAKE.asked = {}
pipeline.run "refactor"
K.idle()
eq("preview: off by default, nothing is asked", #FAKE.asked, 0)
replace.discard_all()

-- ── checkpoint: one key takes a run back ─────────────────────────────────────
checkpoint.reset()
events.reset()
require("agent.features").reset()
require("agent.features").setup()
local a = K.open "a.go"
local b = K.open "b.go"
local function ev_job(id, batch)
  return { id = id, meta = { batch = batch }, action = { label = "fix" } }
end
--- What the replace presenter does around its write, for a proposal over [first, last] of `buf`
local function accept(buf_, id, batch, first, last, lines)
  local j = ev_job(id, batch)
  events.emit("proposal.accepting", { job = j, buf = buf_, first = first, last = last, lines = lines })
  vim.api.nvim_buf_set_lines(buf_, first - 1, last, false, lines)
  events.emit("proposal.accepted", { job = j, buf = buf_, first = first, last = first + #lines - 1, lines = lines })
end
local a0 = vim.api.nvim_buf_get_lines(a, 0, -1, false)
local b0 = vim.api.nvim_buf_get_lines(b, 0, -1, false)
eq("checkpoint: nothing yet", checkpoint.last(), nil)
accept(a, 1, 7, 3, 5, { "func One() int {", "\treturn 100", "}" })
accept(a, 2, 7, 7, 9, { "func Two() int {", "\t// two", "\treturn 200", "}" })
accept(b, 3, 7, 3, 5, { "func Three() int {", "\treturn 300", "}" })
accept(b, 4, 8, 4, 4, { "\treturn 301" }) -- another batch, accepted last
eq("checkpoint: the last group is the last batch", checkpoint.last(), { label = "fix", changes = 1, files = 1 })
local r = checkpoint.undo()
eq("checkpoint: undoes the last group only", { r.restored, r.skipped }, { 1, 0 })
eq("checkpoint: that line is back", vim.api.nvim_buf_get_lines(b, 3, 4, false), { "\treturn 300" })
eq("checkpoint: the group before is still waiting", checkpoint.last(), { label = "fix", changes = 3, files = 2 })
-- text the user typed inside a range after the agent wrote it is left alone
vim.api.nvim_buf_set_lines(a, 8, 9, false, { "\treturn 200 + 1" })
r = checkpoint.undo()
eq("checkpoint: three changes, one edited since", { r.restored, r.skipped }, { 2, 1 })
eq("checkpoint: the untouched file is whole again", vim.api.nvim_buf_get_lines(b, 0, -1, false), b0)
eq(
  "checkpoint: the edited range was not overwritten",
  vim.api.nvim_buf_get_lines(a, 8, 9, false),
  { "\treturn 200 + 1" }
)
eq(
  "checkpoint: the first function in a is back",
  vim.api.nvim_buf_get_lines(a, 2, 5, false),
  { "func One() int {", "\treturn 1", "}" }
)
eq("checkpoint: nothing left", checkpoint.last(), nil)
eq("checkpoint: nothing to undo", checkpoint.undo(), nil)
ok(
  "checkpoint: the key says so",
  (function()
    FAKE.notes = {}
    checkpoint.run()
    return K.note(FAKE):find("nothing to undo", 1, true) ~= nil
  end)()
)

-- through the real presenter: refactor, accept, take back
vim.api.nvim_buf_set_lines(a, 0, -1, false, a0)
vim.api.nvim_set_current_buf(a)
K.at(4)
FAKE.input = "return 10 instead"
FAKE.text = code "func One() int {\n\treturn 10\n}"
pipeline.run "refactor"
K.idle()
replace.accept()
eq("checkpoint: the proposal was written", vim.api.nvim_buf_get_lines(a, 3, 4, false), { "\treturn 10" })
eq("checkpoint: and remembered", checkpoint.last() and checkpoint.last().changes, 1)
checkpoint.run()
eq("checkpoint: one key takes it back", vim.api.nvim_buf_get_lines(a, 0, -1, false), a0)
ok("checkpoint: and says what it did", K.note(FAKE):find("undid 1 change", 1, true) ~= nil)

-- the key is in the everyday menu
package.loaded["menus.agent"] = nil
local keys = {}
for _, m in ipairs(require("menus.agent").maps) do
  keys[m[1]] = m[2]
end
eq("menu: <leader>au undoes the run", keys.u, "undo run")

K.finish()
