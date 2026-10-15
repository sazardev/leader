-- ── Cost summary of a call ───────────────────────────────────────────────────
local jobs = require "agent.jobs"
local text = require "agent.text"

local M = {}

--- "1.4s · 1.2k tok · $0.0021" (whatever the backend does not report does not appear)
---@param job AgentJob
---@param result table
---@return string
function M.line(job, result)
  local u = result.usage or {}
  if u.cached then
    local saved = u.saved_cost and u.saved_cost > 0 and (" · saved $%.4f"):format(u.saved_cost)
      or (u.saved_tokens and u.saved_tokens > 0 and (" · saved %s tok"):format(text.tokens(u.saved_tokens)))
      or ""
    return "cached · 0 tok" .. saved
  end
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
