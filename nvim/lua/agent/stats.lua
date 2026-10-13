-- ── Resumen de coste de una llamada ──────────────────────────────────────────
local jobs = require "agent.jobs"
local text = require "agent.text"

local M = {}

--- "1.4s · 1.2k tok · $0.0021" (lo que el backend no informe, no aparece)
---@param job AgentJob
---@param result table
---@return string
function M.line(job, result)
  local u = result.usage or {}
  local parts = { ("%.1fs"):format(jobs.elapsed(job)) }
  if u.tokens_in then
    parts[#parts + 1] = ("%s→%s tok"):format(text.tokens(u.tokens_in), text.tokens(u.tokens_out or 0))
  end
  if u.cost and u.cost > 0 then
    parts[#parts + 1] = ("$%.4f"):format(u.cost)
  end
  return table.concat(parts, " · ")
end

return M
