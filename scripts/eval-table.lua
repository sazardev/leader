-- `make eval-table`: the published numbers, from the committed baselines (evals/baselines/*.json), no model is called.
-- Writes evals/RESULTS.md. A number in the docs comes from here, never from a hand.
local root = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
local evals = require "agent.eval"
local report = require "agent.eval.report"

local files = vim.fn.glob(root .. "/evals/baselines/*.json", false, true)
table.sort(files)
if #files == 0 then
  io.stdout:write "eval-table: no baselines in evals/baselines/ (make eval MODELS=… EVAL_OUT=evals/baselines/<name>.json)\n"
  return vim.cmd "cquit 1"
end

local lines = {
  "# Eval results",
  "",
  "Measured by `make eval` on the cases in this folder, from the baselines in `evals/baselines/`. Regenerate with `make eval-table`.",
  "pass@1 = the share of single tries that passed; pass@k = the share of cases with at least one passing sample; usable = the output",
  "could be read at all; tries = calls per sample (repairs and steps included); per pass = what one passing answer cost.",
  "",
}
for _, file in ipairs(files) do
  local results = evals.load(file) or {}
  local name = vim.fn.fnamemodify(file, ":t:r")
  local models, cases, samples = {}, {}, 0
  for _, r in ipairs(results) do
    models[r.model] = true
    cases[r.case] = true
    samples = math.max(samples, r.sample or 1)
  end
  lines[#lines + 1] = ("## %s"):format(name)
  lines[#lines + 1] = ""
  lines[#lines + 1] = ("%d cases × up to %d sample(s) · %s"):format(
    vim.tbl_count(cases),
    samples,
    table.concat(vim.tbl_keys(models), ", ")
  )
  lines[#lines + 1] = ""
  vim.list_extend(lines, report.markdown(report.aggregate(results)))
  local failures = report.failures(results)
  if #failures > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Failed:"
    lines[#lines + 1] = ""
    for _, f in ipairs(failures) do
      lines[#lines + 1] = "- " .. f
    end
  end
  lines[#lines + 1] = ""
end
vim.fn.writefile(lines, root .. "/evals/RESULTS.md")
io.stdout:write("eval-table: evals/RESULTS.md from " .. #files .. " baseline(s)\n")
vim.cmd "qa!"
