-- Instructions that are several things, run as a chain of single steps (agent/decompose.lua). Hermetic: no network or tokens.
local ROOT = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
local K = dofile(ROOT .. "/scripts/agent-kit.lua")
local eq, ok = K.eq, K.ok

local decompose = require "agent.decompose"
local settings = require("core.settings").agent

-- ── splitting (pure) ─────────────────────────────────────────────────────────
eq("one thing is one thing", decompose.steps "rename the parameter to value", nil)
eq("empty is nothing", { decompose.steps "", decompose.steps(nil), decompose.steps "   " }, { nil, nil, nil })
eq(
  "semicolons, after a 'do three things:' header",
  decompose.steps "do three things: rename d to data; build result with a comprehension; compute total with sum()",
  { "rename d to data", "build result with a comprehension", "compute total with sum()" }
)
eq(
  "a lead clause and 'and'",
  decompose.steps "return (int, error) instead of panicking: an error for division by zero; and drop the debug Println",
  { "return (int, error) instead of panicking: an error for division by zero", "drop the debug Println" }
)
eq(
  "a numbered list",
  decompose.steps "1. rename x to value\n2) add type hints\n3. return early",
  { "rename x to value", "add type hints", "return early" }
)
eq("a bulleted list", decompose.steps "- extract the loop\n* add a log line", { "extract the loop", "add a log line" })
eq("then", decompose.steps "rename the function, then add a docstring", { "rename the function", "add a docstring" })
eq("a bare comma is a sentence, not two steps", decompose.steps "rename it, keeping the signature", nil)
eq("a semicolon inside parentheses or quotes is not a split", decompose.steps 'replace f(a; b) with g("x; y")', nil)
eq("no more than five: the tail is merged", #decompose.steps "a; b; c; d; e; f; g; h", 5)
eq("the merged tail keeps its words", decompose.steps("a; b; c; d; e; f")[5], "e; f")
eq("a single bullet is not a list", decompose.steps "- do the one thing", nil)

-- ── which jobs are chains ────────────────────────────────────────────────────
local refactor = { decomposable = true }
local multi = "rename a; add b"
eq("a profile that decomposes + an action that opts in", #decompose.plan(refactor, multi, { decompose = true }), 2)
eq("a strong profile does not", decompose.plan(refactor, multi, { decompose = false }), nil)
eq("an action that does not opt in does not", decompose.plan({}, multi, { decompose = true }), nil)
eq("no profile, no chain", decompose.plan(refactor, multi, nil), nil)
eq("one instruction is not a chain", decompose.plan(refactor, "rename a", { decompose = true }), nil)
local text = decompose.step_input("rename a; add b", { "rename a", "add b" }, 1)
ok(
  "step 1 says what to do and what not yet",
  text:find("ONLY step 1 of 2 now: rename a", 1, true) and text:find("do not do them yet", 1, true)
)
text = decompose.step_input("rename a; add b", { "rename a", "add b" }, 2)
ok(
  "step 2 says the earlier ones are applied",
  text:find("already applied", 1, true) and not text:find("do not do them yet", 1, true)
)

-- ── a project and a fake model ───────────────────────────────────────────────
K.project {
  ["go.mod"] = { "module example.com/p", "", "go 1.21" },
  ["a.go"] = { "package p", "", "func One() int {", "\tx := 1", "\treturn x", "}" },
}
local FAKE = K.fake()
settings.verify.command = false
local replace = require "agent.output.replace"
local pipeline = require "agent.pipeline"
local buf = K.open "a.go"
K.at(4)
local function code(body)
  return "```go\n" .. body .. "\n```"
end
settings.capability.models["fakeagent/default"] = "small"

--- The instruction of the request the fake model got (the framing line the chain adds)
local function step_of(req)
  return req.prompt:match "ONLY step (%d) of %d" or "plain"
end

FAKE.input = "rename x to count; return count plus one"
FAKE.text = function(req)
  local step = step_of(req)
  if step == "1" then
    return code "func One() int {\n\tcount := 1\n\treturn count\n}"
  end
  -- step 2 must see what step 1 produced
  if not req.prompt:find("count := 1", 1, true) then
    return code "func One() int {\n\tWRONG\n}"
  end
  return code "func One() int {\n\tcount := 1\n\treturn count + 1\n}"
end
pipeline.run "refactor"
K.idle()
local job = require("agent.jobs").last()
eq("a two-step instruction makes two calls", FAKE.calls, 2)
eq("the job knows its steps", { #job.steps, job.step }, { 2, 2 })
eq("each call carried its own step", { step_of(FAKE.reqs[1]), step_of(FAKE.reqs[2]) }, { "1", "2" })
ok("step 1 saw the original code", FAKE.reqs[1].prompt:find("x := 1", 1, true) ~= nil)
ok(
  "step 2 saw the code step 1 produced",
  FAKE.reqs[2].prompt:find("count := 1", 1, true) ~= nil and not FAKE.reqs[2].prompt:find("x := 1", 1, true)
)
ok("the proposal is the last step's code", job.proposal and job.proposal.lines[3] == "\treturn count + 1")
eq("the proposal is diffed against the ORIGINAL", job.target.lines[2], "\tx := 1")
eq("the bill is every step's", { job.result.usage.tokens_in, job.result.usage.attempts }, { 200, 2 })
replace.accept()
eq(
  "accepting writes the chain's result",
  vim.api.nvim_buf_get_lines(buf, 3, 5, false),
  { "\tcount := 1", "\treturn count + 1" }
)
require("agent.checkpoint").run()
eq("and one key takes it all back", vim.api.nvim_buf_get_lines(buf, 3, 5, false), { "\tx := 1", "\treturn x" })
replace.discard_all()

-- the budget and the preflight see the chain
FAKE.calls, FAKE.asked = 0, {}
settings.budget.confirm_tokens = 1
FAKE.answer = "no"
pipeline.run "refactor"
K.wait(function()
  return #FAKE.asked > 0
end)
K.idle()
eq("the budget guard asked before the chain began", FAKE.calls, 0)
settings.budget.confirm_tokens = 24000
FAKE.answer = "yes"
settings.trust.preflight = "notify"
FAKE.notes = {}
pipeline.run "refactor"
K.idle()
ok(
  "the preflight says how many steps",
  (function()
    for _, n in ipairs(FAKE.notes) do
      if n:find("2 steps", 1, true) then
        return true
      end
    end
    return false
  end)()
)
settings.trust.preflight = "status"
replace.discard_all()

-- a broken step is repaired before the chain moves on
FAKE.calls, FAKE.reqs = 0, {}
FAKE.text = function(req)
  local step = step_of(req)
  if req.prompt:find("<previous-answer>", 1, true) then
    return code "func One() int {\n\tcount := 1\n\treturn count\n}"
  end
  if step == "1" then
    return "I will rename it."
  end
  return code "func One() int {\n\tcount := 1\n\treturn count + 1\n}"
end
pipeline.run "refactor"
K.idle()
eq("step 1 asked twice (a repair), step 2 once", FAKE.calls, 3)
ok("the repair kept the step's own framing", FAKE.reqs[2].prompt:find("ONLY step 1 of 2", 1, true) ~= nil)
ok("and the chain finished", require("agent.jobs").last().proposal ~= nil)
replace.discard_all()

-- imports from every step are kept, the note of the last one wins
FAKE.calls = 0
FAKE.text = function(req)
  if step_of(req) == "1" then
    return code "func One() int {\n\treturn 1\n}" .. "\nneeds-import: fmt\nnote: first"
  end
  return code "func One() int {\n\treturn 2\n}" .. "\nneeds-import: strings"
end
pipeline.run "refactor"
K.idle()
job = require("agent.jobs").last()
eq("the chain's imports are all asked for", job.result.text:match "needs%-import: ([^\n]+)", "fmt, strings")
ok("the earlier note is kept", job.result.text:find("note: first", 1, true) ~= nil)
replace.discard_all()

-- a strong model, or one instruction, is one call as always
settings.capability.models["fakeagent/default"] = "strong"
FAKE.calls = 0
FAKE.text = code "func One() int {\n\treturn 3\n}"
pipeline.run "refactor"
K.idle()
eq("a strong model does it in one call", FAKE.calls, 1)
replace.discard_all()
settings.capability.models["fakeagent/default"] = "small"
FAKE.calls, FAKE.input = 0, "just one thing"
pipeline.run "refactor"
K.idle()
eq("a single instruction is one call", FAKE.calls, 1)
replace.discard_all()

-- the eval can force it on a model whose class would not
settings.capability.models["fakeagent/default"] = nil
local runner = require "agent.eval.runner"
local cases = require "agent.eval.cases"
local c = cases.select(cases.list(), "refactor/py-three-edits")[1]
FAKE.text = function(req)
  local step = step_of(req)
  if step == "1" then
    return "```python\ndef summarize(data):\n    result = {}\n    return result\n```"
  elseif step == "2" then
    return "```python\ndef summarize(data):\n    result = {k: v for k, v in data.items()}\n    return result\n```"
  end
  return "```python\ndef summarize(data):\n    result = {k: v for k, v in data.items()}\n    return result, sum(result.values())\n```"
end
FAKE.input = nil
local r = runner.run(c, { backend = "fakeagent", model = "m", root = cases.root(), decompose = true })
eq("eval: decompose=true runs the chain whatever the class", r.attempts, 3)
FAKE.text = "```python\ndef summarize(data):\n    return {}, 0\n```"
r = runner.run(c, { backend = "fakeagent", model = "m", root = cases.root(), decompose = false })
eq("eval: decompose=false does not", r.attempts, 1)
eq(
  "eval: the settings are put back",
  { settings.capability.small.decompose, settings.capability.medium.decompose, settings.capability.strong.decompose },
  { nil, nil, nil }
)

K.finish()
