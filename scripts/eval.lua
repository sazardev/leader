-- `make eval`: runs the cases in evals/ against models and prints pass rates (agent/eval). Settings come from the
-- environment so the Makefile and CI can drive it:
--   EVAL_MODELS     "claude/haiku,ollama/qwen2.5-coder:7b" (default: the agent's current main model; "replay/golden" = free)
--   EVAL_FILTER     ids containing any of these words ("fix,docs/py")
--   EVAL_SPLIT      dev | holdout (default: both)
--   EVAL_SAMPLES    runs per case and model (default 1; 3 or more for a real measurement)
--   EVAL_MAX_USD    stop asking once this much was spent (default 1.00; 0 = no cap)
--   EVAL_RECORD=1   keep every live answer as a cassette (evals/cassettes/…)
--   EVAL_SCAFFOLD=0 the model on its own: no repairs, schema or cascade (run it with and without to see what the pipeline adds)
--   EVAL_DECOMPOSE=1|0  force the chain of single steps on/off for multi-part instructions (default: the model's profile decides)
--   EVAL_PROFILE=1  turn the pass rates into capability profiles (agent/profiles.lua) and keep them: the pipeline then uses
--                   what was measured, per model and action
--   EVAL_OUT        results JSON (default evals/results/last.json)
--   EVAL_MD         also write the table as Markdown to this path
--   EVAL_BASELINE   a results JSON to compare with: exits 1 when an action × model got worse by EVAL_TOLERANCE (0.1)
local evals = require "agent.eval"
local report = require "agent.eval.report"
local root = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()

local function out(...)
  io.stdout:write(table.concat(vim.tbl_map(tostring, { ... }), " "), "\n")
end

local models = {}
for spec in (vim.env.EVAL_MODELS or ""):gmatch "[^,%s]+" do
  models[#models + 1] = spec
end
if #models == 0 then
  local sel = require("agent.selection").current(nil)
  if not sel then
    out "eval: no agent backend available and EVAL_MODELS is empty"
    return vim.cmd "cquit 2"
  end
  models[1] = sel.backend .. "/" .. (sel.model or "default")
end

local max_usd = tonumber(vim.env.EVAL_MAX_USD or "1.00")
local opts = {
  models = models,
  filter = vim.env.EVAL_FILTER,
  split = (vim.env.EVAL_SPLIT or "") ~= "" and vim.env.EVAL_SPLIT or nil,
  samples = tonumber(vim.env.EVAL_SAMPLES or "1"),
  max_usd = max_usd and max_usd > 0 and max_usd or nil,
  record = vim.env.EVAL_RECORD == "1",
  scaffold = vim.env.EVAL_SCAFFOLD ~= "0",
  decompose = ({ ["1"] = true, ["0"] = false })[vim.env.EVAL_DECOMPOSE or ""],
  on_result = function(r)
    local mark = r.status == "skipped" and "skip" or (r.pass and "ok  " or "FAIL")
    local why = r.pass and "" or (" · " .. (r.error or table.concat(r.failed or {}, ",")))
    out(("%s %s · %s%s%s"):format(mark, r.case, r.model, r.sample > 1 and (" #" .. r.sample) or "", why))
  end,
}
out(
  ("eval: %s · filter=%s · samples=%d · cap=%s"):format(
    table.concat(models, ", "),
    opts.filter or "all",
    opts.samples,
    opts.max_usd and ("$%.2f"):format(opts.max_usd) or "none"
  )
)

local results, groups = evals.run(opts)
out ""
for _, line in ipairs(report.markdown(groups)) do
  out(line)
end
local failures = report.failures(results)
if #failures > 0 then
  out("\nfailed (" .. #failures .. "):")
  for _, line in ipairs(failures) do
    out("  " .. line)
  end
end

if vim.env.EVAL_PROFILE == "1" then
  local measured = require("agent.profiles").from_results(groups)
  require("agent.profiles").save(measured)
  for model, m in pairs(measured) do
    out(
      ("profile %s: %s%s"):format(
        model,
        m.class,
        next(m.declined) and (" · declined: " .. table.concat(vim.tbl_keys(m.declined), ", ")) or ""
      )
    )
  end
end

local path = vim.env.EVAL_OUT or (root .. "/evals/results/last.json")
evals.save(path, results)
out("\nresults: " .. path)
if vim.env.EVAL_MD and vim.env.EVAL_MD ~= "" then
  local md = {
    ("Eval run %s · %s · %d sample(s) per case"):format(os.date "%Y-%m-%d", table.concat(models, ", "), opts.samples),
    "",
  }
  vim.list_extend(md, report.markdown(groups))
  vim.fn.writefile(md, vim.env.EVAL_MD)
  out("table: " .. vim.env.EVAL_MD)
end

if vim.env.EVAL_BASELINE and vim.env.EVAL_BASELINE ~= "" then
  local baseline = evals.load(vim.env.EVAL_BASELINE)
  if not baseline then
    out("baseline not readable: " .. vim.env.EVAL_BASELINE)
    return vim.cmd "cquit 2"
  end
  local worse = report.regressions(report.aggregate(baseline), groups, tonumber(vim.env.EVAL_TOLERANCE or "0.1"))
  for _, r in ipairs(worse) do
    out(("REGRESSION %s · %s: pass@1 %d%% → %d%%"):format(r.action, r.model, r.was * 100, r.now * 100))
  end
  if #worse > 0 then
    return vim.cmd "cquit 1"
  end
  out "no regression against the baseline"
end
vim.cmd "qa!"
