-- ── Evals: how good is the agent, with which model? ──────────────────────────
-- `make eval` runs the cases in `evals/` (agent/eval/cases.lua) through the real pipeline against a list of models and
-- prints pass rates per action × model. The point is a measured answer to "can a smaller model do this action well?":
-- which actions are model-agnostic, which need scaffolding, and whether a prompt change helped or hurt.
--
--   models       "backend/model" specs: "claude/haiku", "ollama/qwen2.5-coder:7b", "replay/golden" (a cassette)
--   filter       ids containing any of these words ("fix,docs/py")
--   split        "dev" | "holdout" (nil = both). Tune prompts on dev; look at holdout to know if it generalised
--   samples      runs per case and model (models are not deterministic: one lucky run is not a result)
--   max_usd      stops asking paid models once this much was spent (the rest are reported as skipped)
--   record       save every live answer as a cassette
--   scaffold     false = measure the model bare (no repairs, schema or cascade): run both to see what the pipeline adds
local cases = require "agent.eval.cases"
local replay = require "agent.eval.replay"
local report = require "agent.eval.report"
local runner = require "agent.eval.runner"

local M = {}

---@param spec string "backend/model"
---@return string backend, string? model
function M.parse_model(spec)
  local backend, model = spec:match "^([^/]+)/(.+)$"
  if backend then
    return backend, model
  end
  return spec, nil
end

---@class AgentEvalOpts
---@field models string[]
---@field filter string?
---@field split string?
---@field samples integer?
---@field max_usd number?
---@field give_up integer? consecutive errors after which a model is given up on (default 3)
---@field record boolean?
---@field scaffold boolean?
---@field decompose boolean?
---@field root string?
---@field on_result fun(result: table)?

---@param opts AgentEvalOpts
---@return table[] results, AgentEvalGroup[] groups
function M.run(opts)
  replay.register()
  local root = opts.root or cases.root()
  local list = cases.select(cases.list(root), opts.filter, opts.split)
  local results, spent = {}, 0
  for _, spec in ipairs(opts.models) do
    local backend, model = M.parse_model(spec)
    local streak, dead = 0, nil -- consecutive errors: a model that cannot be reached is not asked 30 more times
    for _, case in ipairs(list) do
      for sample = 1, opts.samples or 1 do
        local result
        if opts.max_usd and spent >= opts.max_usd then
          result = {
            case = case.id,
            action = case.action,
            model = spec,
            sample = sample,
            status = "skipped",
            error = "budget reached",
          }
        elseif dead then
          result =
            { case = case.id, action = case.action, model = spec, sample = sample, status = "skipped", error = dead }
        else
          result = runner.run(case, {
            backend = backend,
            model = model,
            sample = sample,
            root = root,
            record = opts.record,
            scaffold = opts.scaffold,
            decompose = opts.decompose,
          })
          spent = spent + (result.cost or 0)
          streak = result.status == "error" and streak + 1 or 0
          if streak >= (opts.give_up or 3) then
            dead = "unreachable after " .. streak .. " errors in a row: " .. report.short(result.error)
          end
        end
        results[#results + 1] = result
        if opts.on_result then
          opts.on_result(result)
        end
      end
    end
  end
  return results, report.aggregate(results)
end

---@param path string
---@param results table[]
function M.save(path, results)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(vim.split(vim.json.encode(results), "\n", { plain = true }), path)
end

---@param path string
---@return table[]?
function M.load(path)
  if vim.fn.filereadable(path) == 0 then
    return nil
  end
  local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
  return ok and data or nil
end

return M
