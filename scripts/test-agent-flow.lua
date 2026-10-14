-- Tests of the agent's spend guard, events, `pipeline.launch`, and verification after accepting: budget (pure), guards,
-- the events bus, a launch denied by a guard, and the whole verify → retry loop with a fake model and simulated LSP
-- diagnostics. Hermetic: no network or tokens.
local ROOT = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
local K = dofile(ROOT .. "/scripts/agent-kit.lua")
local eq, ok = K.eq, K.ok

local budget = require "agent.budget"
local events = require "agent.events"
local settings = require("core.settings").agent

-- ── budget (pure) ───────────────────────────────────────────────────────────
eq("tokens: ~3.5 chars each", budget.tokens(350), 100)
local runs = {
  { backend = "claude", model = "sonnet", ts = 1000, usage = { tokens_in = 1000, cost = 0.004 } },
  { backend = "claude", model = "sonnet", ts = 2000, usage = { tokens_in = 1000, cost = 0.006 } },
  { backend = "claude", model = "haiku", ts = 2000, usage = { tokens_in = 1000, cost = 0.0004 } },
  { t = "event", id = "x", ts = 2000 },
}
eq("price per token: the model's own history", budget.price_per_token(runs, "claude", "sonnet"), 0.000005)
eq("price per token: unknown model has none", budget.price_per_token(runs, "claude", "opus"), nil)
eq("spent since: only what is after, events ignored", budget.spent_since(runs, 1500), 0.0064)
local ctx = { runs = runs, now = 3000, session_start = 0 }
local req = { action = "fix", backend = "claude", model = "sonnet", chars = 3500 }
eq("check: a small request is ok", budget.check(req, { confirm_tokens = 24000 }, ctx).level, "ok")
eq(
  "check: a big request asks",
  budget.check({ action = "x", chars = 100000 }, { confirm_tokens = 24000 }, ctx).level,
  "confirm"
)
eq(
  "check: an expensive one asks",
  budget.check({ action = "x", backend = "claude", model = "sonnet", chars = 70000 }, { confirm_usd = 0.05 }, ctx).level,
  "confirm"
)
local blocked = budget.check(req, { day_usd = 0.01, session_usd = nil }, { runs = runs, now = 1500, session_start = 0 })
eq("check: a used-up cap blocks", blocked.level, "block")
ok("check: the reason says which cap", blocked.reasons[1]:find("today", 1, true) ~= nil)
eq(
  "check: near a cap it asks first",
  budget.check(req, { session_usd = 0.018, warn_ratio = 0.8 }, ctx).level,
  "confirm"
)
eq(
  "check: an estimate that would cross the cap blocks",
  budget.check(req, { session_usd = 0.0115 }, ctx).level,
  "block"
)
eq("check: a batch counts every request", budget.check({ action = "x", chars = 7000, count = 4 }, {}, ctx).tokens, 8000)
eq("describe: tokens and cost", budget.describe { tokens = 1800, cost = 0.0007 }, "~1.8k tokens · ~$0.0007")
eq(
  "describe: small and round numbers",
  { budget.describe { tokens = 498 }, budget.describe { tokens = 24000 } },
  { "~498 tokens", "~24k tokens" }
)
eq(
  "check: the reason uses the same units",
  budget.check({ action = "x", chars = 1750 }, { confirm_tokens = 200 }, ctx).reasons[1],
  "~500 tokens (it asks above 200)"
)

-- ── events ──────────────────────────────────────────────────────────────────
events.reset()
local seen = {}
local off = events.on("t", function(p)
  seen[#seen + 1] = p.n
end)
events.on("t", function()
  error "a broken handler"
end)
events.on("t", function(p)
  seen[#seen + 1] = p.n * 10
end)
events.emit("t", { n = 1 })
eq("events: every handler runs, in order, and a broken one does not stop the rest", seen, { 1, 10 })
off()
events.emit("t", { n = 2 })
eq("events: unsubscribed handlers stop", seen, { 1, 10, 20 })
events.reset()

-- ── a project and a fake model ──────────────────────────────────────────────
local dir = K.project {
  ["go.mod"] = { "module example.com/p", "", "go 1.21" },
  ["store.go"] = {
    "package p", -- 1
    "", -- 2
    "type Note struct{ Title string }", -- 3
    "", -- 4
    "func Rename(n *Note, title string) error {", -- 5
    "\tn.Title = title", -- 6
    "\treturn nil", -- 7
    "}", -- 8
  },
}
local FAKE = K.fake()
settings.verify.settle_ms = 60
settings.verify.max_wait_ms = 900
settings.verify.command = false
local replace = require "agent.output.replace"
local pipeline = require "agent.pipeline"
local actions = require "agent.actions"

local buf = K.open "store.go"
local NS = vim.api.nvim_create_namespace "test-lsp"
local function diag(line, msg)
  return { lnum = line - 1, col = 0, severity = vim.diagnostic.severity.ERROR, message = msg, source = "gopls" }
end

local function fix_text(body)
  return "```go\n" .. body .. "\n```"
end
local FIXED = "func Rename(n *Note, title string) error {\n\tn.Title = title\n\treturn nil\n}"
local FIXED_B = "func Rename(n *Note, title string) error {\n\t// renamed\n\tn.Title = title\n\treturn nil\n}"

-- ── pipeline.launch: the budget denies it before anything is sent ───────────
settings.budget.confirm_tokens = 1 -- everything is "bigger than usual"
FAKE.answer = "no"
local settled
events.on("job.settled", function(ev)
  settled = ev.outcome
end)
vim.diagnostic.set(NS, buf, { diag(6, "undefined: x") })
K.at(6)
FAKE.text = fix_text(FIXED)
pipeline.run "fix_block"
K.wait(function()
  return settled ~= nil
end)
eq("guard: saying no stops the job as denied", settled, "denied")
eq("guard: and no request was made", FAKE.calls, 0)
eq("guard: it asked, with the budget title", FAKE.asked[1] and FAKE.asked[1].title, "Agent budget")
eq("guard: nothing is left running", #require("agent.jobs").running(), 0)

FAKE.answer = "yes"
settled = nil
pipeline.run "fix_block"
K.idle()
eq("guard: saying yes lets it through", FAKE.calls, 1)
eq("guard: and the job settles as done", settled, "done")
settings.budget.confirm_tokens = 24000
replace.discard_all()

-- a hard cap blocks without asking
settings.budget.day_usd = 0.00001
settled = nil
FAKE.asked = {}
pipeline.run "fix_block"
K.wait(function()
  return settled ~= nil
end)
eq("guard: a used-up daily cap blocks without asking", { settled, #FAKE.asked }, { "denied", 0 })
ok("guard: and says why", K.note(FAKE):find("budget", 1, true) ~= nil)
settings.budget.day_usd = nil

-- ── verification after accepting ────────────────────────────────────────────
local verify = require "agent.verify"
local regs = require "agent.verify.regressions"
local E = vim.diagnostic.severity.ERROR
eq("regressions: same message one line lower is not new", #regs.new({ diag(5, "boom") }, { diag(9, "boom") }, E), 0)
eq(
  "regressions: a new message is",
  regs.new({ diag(5, "boom") }, { diag(9, "boom"), diag(3, "other") }, E)[1].message,
  "other"
)
eq(
  "regressions: a multiset (3 before, 4 after = 1 new)",
  #regs.new({ diag(1, "a"), diag(2, "a"), diag(3, "a") }, { diag(1, "a"), diag(2, "a"), diag(3, "a"), diag(4, "a") }, E),
  1
)
eq(
  "regressions: warnings do not count when only errors do",
  #regs.new({}, { { lnum = 0, severity = vim.diagnostic.severity.WARN, message = "w" } }, E),
  0
)
eq("regressions: described short", regs.describe({ diag(12, "undefined: x\nsecond line") }, 3), { "L12 undefined: x" })

-- the whole loop: accept → the "LSP" reports a NEW error → it offers a retry → the retry proposal → accept …
events.reset()
require("agent.features").reset()
verify.reset()
pipeline = require "agent.pipeline" -- (already loaded: setup() runs when features is wired)
require("agent.features").setup()
vim.diagnostic.set(NS, buf, { diag(6, "unused: old") })
FAKE.calls, FAKE.asked, FAKE.reqs = 0, {}, {}
K.at(6)
-- the first request answers with code that has a problem; the retry (recognized by its framing) answers with the fix
FAKE.text = function(req)
  if req.system:find("TASK fix a regression", 1, true) then
    return fix_text(FIXED_B)
  end
  return fix_text "func Rename(n *Note, title string) error {\n\tn.Title = title + undefinedThing\n\treturn nil\n}"
end
pipeline.run "fix_block"
K.idle()
replace.accept()
-- the language server answers a moment later: the old one is gone and a NEW one appeared on the accepted code
vim.defer_fn(function()
  vim.diagnostic.set(NS, buf, { diag(6, "undefined: undefinedThing") })
end, 120)
K.wait(function()
  return #FAKE.asked > 0
end, 4000)
local asked = FAKE.asked[1]
eq("verify: a new error after accepting asks about a retry", asked and asked.title, "fix regression 1/2")
local text = vim.inspect(asked and asked.lines or {})
ok("verify: the question names the problem", text:find("undefined: undefinedThing", 1, true) ~= nil)
ok("verify: and which attempt it is", text:find("attempt 1 of 2", 1, true) ~= nil)

K.idle()
eq("verify: yes → one more request", FAKE.calls, 2)
ok(
  "verify: the retry prompt carries the regression framing",
  FAKE.req.system:find("TASK fix a regression", 1, true) ~= nil
)
local pending = replace.pending()
eq("verify: and its proposal is waiting", #pending, 1)
eq("verify: the attempt travels with the job", pending[1] and pending[1].job.meta.attempt, 1)

-- no new problem → no question, just a quiet line
FAKE.asked, FAKE.notes = {}, {}
replace.discard_all()
vim.diagnostic.set(NS, buf, {})
vim.cmd("silent edit! " .. dir .. "/store.go")
buf = vim.api.nvim_get_current_buf()
vim.bo[buf].filetype = "go"
vim.diagnostic.set(NS, buf, { diag(6, "old problem") })
K.at(6)
FAKE.text = fix_text(FIXED_B)
pipeline.run "fix_block"
K.idle()
replace.accept()
vim.defer_fn(function()
  vim.diagnostic.set(NS, buf, { diag(6, "old problem") }) -- the same problem the buffer already had
end, 120)
K.wait(function()
  return K.note(FAKE):find("verified", 1, true) ~= nil
end, 4000)
ok(
  "verify: nothing new → a quiet confirmation, no question",
  K.note(FAKE):find("no new problems", 1, true) ~= nil and #FAKE.asked == 0
)

-- the retry limit: after max_retries it stops offering
events.reset()
require("agent.features").reset()
verify.reset()
require("agent.features").setup()
settings.verify.max_retries = 1
local calls_before = FAKE.calls
FAKE.asked, FAKE.notes = {}, {}
FAKE.text = fix_text(FIXED)
local job = { action = actions.get "fix_block", meta = { attempt = 1 }, record_id = "r" }
require("agent.verify.retry").offer { buf = buf, diagnostics = { diag(6, "still broken") }, job = job, source = "lsp" }
eq("retry: past the limit it does not ask or call the model", { #FAKE.asked, FAKE.calls }, { 0, calls_before })
ok("retry: and says so", K.note(FAKE):find("no attempts left", 1, true) ~= nil)

-- ── the guard also covers one-shot calls (commit draft, staged review, plan) ─
local agent = require "agent"
FAKE.calls, FAKE.asked = 0, {}
settings.budget.day_usd = 0.00001
local blocked_ok, blocked_msg
local handle = agent.complete({ action = "commit", system = "s", prompt = "p" }, function(ok, msg)
  blocked_ok, blocked_msg = ok, msg
end)
K.wait(function()
  return blocked_ok ~= nil
end, 3000)
eq(
  "one-shot: a used-up cap stops a commit draft before any request",
  { blocked_ok, blocked_msg, FAKE.calls, handle },
  { false, "stopped by the spend budget", 0, nil }
)
settings.budget.day_usd = nil
settings.budget.confirm_tokens = 0 -- any request is "bigger than usual"
FAKE.answer = "no"
local asked_ok
agent.complete({ action = "commit", system = "s", prompt = "p" }, function(ok)
  asked_ok = ok
end)
K.wait(function()
  return asked_ok ~= nil
end, 3000)
eq("one-shot: a big one asks, and no stops it", { asked_ok, #FAKE.asked, FAKE.calls }, { false, 1, 0 })
FAKE.answer = "yes"
local done_ok, done_text
agent.complete({ action = "commit", system = "s", prompt = "p" }, function(ok, text)
  done_ok, done_text = ok, text
end)
K.wait(function()
  return done_ok ~= nil
end, 3000)
local recorded = vim.tbl_filter(function(r)
  return r.output == "oneshot" and r.action == "commit"
end, require("agent.runs.store").read())
eq("one-shot: yes sends it, and the call is in the history", { done_ok, FAKE.calls, #recorded }, { true, 1, 1 })
settings.budget.confirm_tokens = 24000

K.finish()
