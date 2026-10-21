-- The measuring and the explaining around the agent: backend error hints, errors kept apart from failures in the report,
-- flakiness and cost per pass, giving up on a model that cannot be reached, and the published table. Hermetic.
local ROOT = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
local K = dofile(ROOT .. "/scripts/agent-kit.lua")
local eq, ok = K.eq, K.ok

local hints = require "agent.backends.hints"
local report = require "agent.eval.report"
local evals = require "agent.eval"

-- ── hints (pure) ─────────────────────────────────────────────────────────────
local gw = hints.explain("opencode", "Forbidden: request was blocked by a gateway or proxy.")
ok(
  "hints: a gateway refusal says what to check",
  gw:find "^Forbidden: request was blocked" and gw:find("account and plan", 1, true)
)
ok(
  "hints: opencode's opaque server error",
  hints
    .explain("opencode", "Unexpected server error. Check server logs for details. (err_1)")
    :find("opencode auth login", 1, true) ~= nil
)
eq(
  "hints: the same text from another backend is not advised as opencode's",
  hints.explain("claude", "Unexpected server error"),
  "Unexpected server error"
)
ok(
  "hints: any backend: out of credit",
  hints.explain("claude", "Credit balance is too low"):find("top it up", 1, true) ~= nil
)
ok(
  "hints: rate limit mentions the cascade",
  hints.explain("claude", "429 rate limit exceeded"):find("cascade", 1, true) ~= nil
)
eq("hints: an unknown error is returned as it came", hints.explain("claude", "something odd"), "something odd")
eq("hints: nothing", hints.explain("claude", nil), "")
eq(
  "hints: the original message is never replaced",
  hints.explain("claude", "Not logged in"):sub(1, 13),
  "Not logged in"
)

-- ── report: errors are not failures ──────────────────────────────────────────
local function res(case, model, extra)
  return vim.tbl_extend("force", {
    case = case,
    action = "fix",
    model = model,
    status = "ok",
    parsed = true,
    applied = true,
    pass = true,
    tokens_in = 100,
    tokens_out = 20,
    cost = 0.01,
    ms = 1000,
    sample = 1,
  }, extra or {})
end
local groups = report.aggregate {
  res("fix/a", "m", { pass = true }),
  res("fix/b", "m", { pass = false }),
  res("fix/c", "m", { status = "error", error = "boom", pass = false, cost = 0 }),
  res("fix/c", "m", { status = "error", error = "boom", pass = false, cost = 0 }),
}
local g = groups[1]
eq("errors are counted apart", { g.n, g.errors }, { 2, 2 })
eq("pass@1 is over the samples that ran", g.pass1, 0.5)
eq("cases that only errored say nothing about the model", g.cases, 2)
local only_errors =
  report.aggregate({ res("fix/a", "dead", { status = "error", error = "x", pass = false, cost = 0 }) })[1]
eq("a model with no sample has no rate", { only_errors.n, only_errors.errors, only_errors.pass1 }, { 0, 1, 0 })
local md = table.concat(report.markdown { only_errors }, "\n")
ok("the table shows a dash, not 0%", md:find("—", 1, true) and not md:find "0%%")
ok(
  "an errors column appears when something errored",
  table.concat(report.markdown { groups[1] }, "\n"):find("errors", 1, true) ~= nil
)
local clean = table.concat(report.markdown(report.aggregate { res("fix/a", "m") }), "\n")
ok("no errors column when nothing errored", not clean:find("errors", 1, true))
eq(
  "a baseline with an unreachable model is not a regression",
  #report.regressions(
    { { action = "fix", model = "m", pass1 = 0.9, n = 4 } },
    { { action = "fix", model = "m", pass1 = 0, n = 0 } }
  ),
  0
)
eq("short: first line, clipped", report.short "first\nsecond", "first")
eq("short: long lines are cut", #report.short(string.rep("x", 300)) <= 100, true)

-- ── flaky and cost per pass ──────────────────────────────────────────────────
local gf = report.aggregate({
  res("fix/a", "m", { sample = 1, pass = true }),
  res("fix/a", "m", { sample = 2, pass = false }),
  res("fix/a", "m", { sample = 3, pass = true }),
  res("fix/b", "m", { sample = 1, pass = true }),
  res("fix/b", "m", { sample = 2, pass = true }),
  res("fix/b", "m", { sample = 3, pass = true }),
  res("fix/c", "m", { sample = 1, pass = false }),
  res("fix/c", "m", { sample = 2, pass = false }),
})[1]
eq("flaky: only cases whose samples disagree", gf.flaky, 1)
eq("pass@k counts a case with any pass", gf.passk, 2 / 3)
eq("cost per pass: total over what passed", gf.per_pass, (8 * 0.01) / 5)
ok(
  "the flaky column shows up when samples repeat",
  table.concat(report.markdown { gf }, "\n"):find("flaky", 1, true) ~= nil
)
eq("free models have no cost per pass", report.aggregate({ res("fix/a", "m", { cost = 0 }) })[1].per_pass, nil)

-- ── giving up on a model that cannot be reached ──────────────────────────────
K.fake()
require("agent.eval.replay").register()
local seen = {}
local results = evals.run {
  models = { "replay/no-such-cassette" },
  filter = "fix",
  split = "dev",
  on_result = function(r)
    seen[#seen + 1] = r.status
  end,
}
local ran, skipped = 0, 0
for _, s in ipairs(seen) do
  if s == "error" then
    ran = ran + 1
  elseif s == "skipped" then
    skipped = skipped + 1
  end
end
eq("three errors in a row and it stops asking", ran, 3)
ok(
  "the rest are skipped with the reason",
  skipped > 0 and results[#results].error:find("unreachable after 3 errors", 1, true) ~= nil
)
local all_errors = evals.run { models = { "replay/no-such-cassette" }, filter = "docs", split = "dev", give_up = 100 }
eq("give_up is configurable", #vim.tbl_filter(function(r)
  return r.status == "error"
end, all_errors), #all_errors)

-- ── the published table ──────────────────────────────────────────────────────
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/evals/baselines", "p")
evals.save(tmp .. "/evals/baselines/some-model.json", {
  res("fix/a", "claude/x", { sample = 1 }),
  res("fix/b", "claude/x", { sample = 1, pass = false, failed = { "cmd" } }),
})
local out = vim
  .system({ "nvim", "--headless", "-c", "luafile " .. ROOT .. "/scripts/eval-table.lua" }, {
    text = true,
    env = { AGENT_TEST_ROOT = tmp },
  })
  :wait()
local table_md = table.concat(vim.fn.readfile(tmp .. "/evals/RESULTS.md"), "\n")
ok("the table is written from a baseline", out.code == 0 and table_md:find("## some-model", 1, true) ~= nil)
ok("with its numbers", table_md:find("claude/x", 1, true) and table_md:find "50%%")
ok("and what failed", table_md:find("fix/b · claude/x · cmd", 1, true) ~= nil)

K.finish()
