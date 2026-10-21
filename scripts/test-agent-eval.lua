-- The eval harness (agent/eval): judges, report, cases, cassettes and the whole road through the pipeline, offline.
-- The most important check is at the bottom: EVERY case in evals/ passes with its golden answer and fails with a do-nothing
-- one, so a case cannot silently become one that everything (or nothing) passes.
local root = vim.env.AGENT_TEST_ROOT
local K = dofile(root .. "/scripts/agent-kit.lua")
local judge = require "agent.eval.judge"
local report = require "agent.eval.report"
local cases = require "agent.eval.cases"
local replay = require "agent.eval.replay"
local runner = require "agent.eval.runner"
local evals = require "agent.eval"

-- ── judges ───────────────────────────────────────────────────────────────────
local before = { "a", "b", "c", "d", "e" }
K.ok("outside: same head and tail", judge.outside_unchanged(before, { "a", "X", "Y", "d", "e" }, 2, 3))
K.ok(
  "outside: a changed line before the target",
  not judge.outside_unchanged(before, { "Z", "X", "c", "d", "e" }, 2, 3)
)
K.ok("outside: a changed line after the target", not judge.outside_unchanged(before, { "a", "X", "c", "d", "Z" }, 2, 3))
K.ok("outside: the tail cannot be eaten", not judge.outside_unchanged(before, { "a", "e" }, 2, 3))
K.eq("new target", judge.new_target({ "a", "X", "Y", "d", "e" }, 2, 2), { "X", "Y" })
K.ok(
  "contains all",
  judge.contains_all("hello world", { "hello", "wor" }) and not judge.contains_all("hello", { "bye" })
)
K.ok("contains none", judge.contains_none("hello", { "bye" }) and not judge.contains_none("hello", { "ell" }))
K.ok(
  "preserves: a docstring added",
  judge.preserves_code({ "def f():", "    return 1" }, { "def f():", '    """Doc."""', "    return 1" })
)
K.ok(
  "preserves: a code line changed",
  not judge.preserves_code({ "def f():", "    return 1" }, { "def f():", "    return 2" })
)
K.ok(
  "preserves: comments may go",
  judge.preserves_code({ "# old", "def f():", "    return 1" }, { "def f():", "    return 1" })
)
K.ok("preserves: order matters", not judge.preserves_code({ "a", "b" }, { "b", "a" }))
K.ok("findings near", judge.findings_near({ { line = 5 } }, { { line = 4, tol = 1 } }))
K.ok("findings far", not judge.findings_near({ { line = 9 } }, { { line = 4, tol = 1 } }))
K.ok("findings default tolerance is 2", judge.findings_near({ { line = 6 } }, { { line = 4 } }))

local answers = judge.judge(
  { contains = { "X" }, preserves = true },
  { before = { "a", "b" }, after = { "a", "X" }, first = 2, last = 2 }
)
K.eq("judge answers", answers, { outside = true, contains = true, preserves = false, changed = true })
K.ok("one no fails the result", not judge.passes(answers))
K.eq("failed lists the noes", judge.failed(answers), { "preserves" })
K.ok("no answers is not a pass", not judge.passes {})
K.eq(
  "nothing applied is not a pass",
  judge.judge({ contains = {} }, { before = { "a" }, after = { "a" }, first = 1, last = 1 }).changed,
  false
)
K.eq(
  "findings judged without scope questions",
  judge.judge(
    { findings = { { line = 3 } }, max_findings = 1 },
    { before = { "a" }, after = { "a" }, first = 1, last = 1, findings = { { line = 3 }, { line = 9 } } }
  ),
  { findings = true, focused = false }
)

-- ── report ───────────────────────────────────────────────────────────────────
local function res(case, model, pass, extra)
  return vim.tbl_extend("force", {
    case = case,
    action = "fix",
    model = model,
    status = "ok",
    parsed = true,
    applied = true,
    pass = pass,
    tokens_in = 100,
    tokens_out = 20,
    cost = 0.01,
    ms = 1000,
  }, extra or {})
end
local groups = report.aggregate {
  res("fix/a", "small", true),
  res("fix/a", "small", false),
  res("fix/b", "small", false),
  res("fix/a", "big", true),
  res("fix/b", "big", true),
  res("fix/c", "big", true, { status = "skipped" }),
}
K.eq("two groups, skipped ignored", #groups, 2)
local small = groups[2]
K.eq("sorted by model", { groups[1].model, small.model }, { "big", "small" })
K.eq("pass@1 is over every sample", small.pass1, 1 / 3)
K.eq("pass@k is over cases", small.passk, 0.5)
K.eq("big passes everything", { groups[1].pass1, groups[1].passk }, { 1, 1 })
K.eq("cost adds up", small.cost, 0.03)
K.eq("tokens are averaged", { small.tokens_in, small.tokens_out }, { 100, 20 })
local md = report.markdown(groups)
K.ok("markdown has a header and a row per group", #md == 4 and md[1]:find("pass@1", 1, true) ~= nil)
K.ok(
  "a free model says free",
  report.markdown(report.aggregate { res("fix/a", "m", true, { cost = 0 }) })[3]:find("free", 1, true) ~= nil
)
K.eq(
  "failures describe themselves",
  report.failures { res("fix/a", "m", false, { failed = { "contains" } }) },
  { "fix/a · m · contains" }
)
K.eq(
  "failures: unusable output",
  report.failures { res("fix/a", "m", false, { parsed = false }) },
  { "fix/a · m · unusable output" }
)
K.eq(
  "a regression is a drop over the tolerance",
  #report.regressions(report.aggregate { res("fix/a", "m", true) }, report.aggregate { res("fix/a", "m", false) }),
  1
)
K.eq(
  "a small drop is tolerated",
  #report.regressions(
    { { action = "fix", model = "m", pass1 = 0.9 } },
    { { action = "fix", model = "m", pass1 = 0.85 } }
  ),
  0
)

-- ── cases ────────────────────────────────────────────────────────────────────
local all = cases.list()
K.ok("there are cases", #all >= 12)
local actions_seen, splits = {}, {}
for _, c in ipairs(all) do
  actions_seen[c.action] = true
  splits[c.split] = true
  local problems = cases.problems(c)
  K.eq("case is well formed: " .. c.id, problems, {})
end
K.ok(
  "fix, docs, refactor and review are covered",
  actions_seen.fix and actions_seen.docs and actions_seen.refactor and actions_seen.review
)
K.ok("there is a holdout", splits.holdout and splits.dev)
K.eq("filter by id", #cases.select(all, "docs"), #vim.tbl_filter(function(c)
  return c.action == "docs"
end, all))
K.ok("filter by comma list", #cases.select(all, "docs,fix") > #cases.select(all, "docs"))
K.ok("split filter", #cases.select(all, nil, "holdout") < #all)
K.ok("a typo in a check key is reported", #cases.problems {
  dir = root,
  split = "dev",
  spec = { file = "Makefile", lang = "make", line = 1, check = { contian = {} } },
} == 1)

-- ── every case passes golden and fails noop ──────────────────────────────────
K.fake() -- isolation (no LSP, in-memory state); the replay backend is the one used below
replay.register()
local function run(case, model)
  return runner.run(case, { backend = "replay", model = model, root = cases.root() })
end
for _, case in ipairs(all) do
  local golden = run(case, "golden")
  K.ok(("golden passes: %s %s"):format(case.id, golden.error or table.concat(golden.failed or {}, ",")), golden.pass)
  local noop = run(case, "noop")
  if case.spec.clean then
    K.ok("noop is the right answer to a clean case: " .. case.id, noop.pass)
  else
    K.ok("noop fails: " .. case.id, not noop.pass)
  end
end

-- ── a broken answer fails for the right reason ───────────────────────────────
local slug = cases.select(all, "docs/py-slugify")[1]
local broken = runner.run(slug, { backend = "fakeagent", model = "m", root = cases.root() })
K.ok(
  "a missing cassette on replay is an error, not a pass",
  (function()
    local r = run(slug, "no-such-model")
    return r.status == "error" and not r.pass
  end)()
)
K.ok("an empty answer from a model is unusable", not broken.pass)

-- ── record a live answer, replay it ──────────────────────────────────────────
local FAKE = K.fake()
local fix = cases.select(all, "fix/py-wrong-type")[1]
FAKE.text = '```python\n    return "Total: " + str(total)\n```'
local tmp = vim.fn.tempname()
for _, name in ipairs { "app.py", "case.json" } do
  vim.fn.mkdir(tmp .. "/fix/py-wrong-type", "p")
  vim.fn.writefile(vim.fn.readfile(fix.dir .. "/" .. name), tmp .. "/fix/py-wrong-type/" .. name)
end
local live = runner.run(
  { id = fix.id, action = fix.action, dir = tmp .. "/fix/py-wrong-type", spec = fix.spec, split = "dev" },
  { backend = "fakeagent", model = "tiny", record = true, root = tmp }
)
K.ok("a live run is judged", live.pass and live.tokens_in == 100 and live.tokens_out == 20)
K.eq("the model name is the backend and model", live.model, "fakeagent/tiny")
local tape = replay.load(tmp, fix.id, "fakeagent/tiny")
K.ok("the answer was recorded", tape and tape.text == FAKE.text and tape.usage.tokens_in == 100)
local played = runner.run(
  { id = fix.id, action = fix.action, dir = tmp .. "/fix/py-wrong-type", spec = fix.spec, split = "dev" },
  { backend = "replay", model = "fakeagent/tiny", root = tmp }
)
K.ok("the cassette replays to the same verdict", played.pass)
K.eq("and the same cost in tokens", played.tokens_in, 100)

-- ── the orchestrator ─────────────────────────────────────────────────────────
local seen = {}
local results, grouped = evals.run {
  models = { "replay/golden", "replay/noop" },
  filter = "fix",
  split = "dev",
  on_result = function(r)
    seen[#seen + 1] = r.case
  end,
}
K.eq("every dev fix case runs on both models", #results, 2 * #cases.select(all, "fix", "dev"))
K.eq("progress is reported per result", #seen, #results)
local by_model = {}
for _, g in ipairs(grouped) do
  by_model[g.model] = g
end
K.eq("golden gets everything", by_model["replay:golden"].pass1, 1)
K.eq("noop gets nothing", by_model["replay:noop"].pass1, 0)
local capped = evals.run { models = { "replay/golden" }, filter = "docs", samples = 2, max_usd = 0 }
K.ok("a spent budget skips the rest", #capped > 0 and capped[1].status == "skipped")
K.eq("model specs parse", { evals.parse_model "ollama/qwen2.5-coder:7b" }, { "ollama", "qwen2.5-coder:7b" })
K.eq("a bare backend has no model", { evals.parse_model "claude" }, { "claude", nil })
local out = vim.fn.tempname() .. "/r/results.json"
evals.save(out, results)
K.eq("results round-trip through JSON", #(evals.load(out) or {}), #results)

K.finish()
