-- ── What this session has spent ──────────────────────────────────────────────
-- A running total of the dollars the agent's calls cost since Neovim started (every action and every one-shot call
-- reports here through agent/runs), so the statusline can show it without reading the history file on every redraw.
-- The cap it is shown against is the budget guard's own `session_usd`: one number, one meaning.
local M = {}

local total, calls = 0, 0

---@param cost number?
function M.add(cost)
  calls = calls + 1
  total = total + (cost or 0)
end

---@return number dollars, integer calls
function M.session()
  return total, calls
end

--- Starts again from zero (tests)
function M.reset()
  total, calls = 0, 0
end

--- "$0.031" or "$0.031/$2.00"; and whether the cap is close (`warn_ratio` of it). Empty before anything was spent: a
--- chip that always says "$0.000" is noise
---@param spent number
---@param cap number? settings.agent.budget.session_usd
---@param warn_ratio number?
---@return string text, boolean near
function M.chip(spent, cap, warn_ratio)
  if spent <= 0 then
    return "", false
  end
  local function usd(x)
    return x >= 1 and ("$%.2f"):format(x) or ("$%.3f"):format(x)
  end
  if not cap then
    return usd(spent), false
  end
  return ("%s/%s"):format(usd(spent), ("$%.2f"):format(cap)), spent >= cap * (warn_ratio or 0.8)
end

--- What the statusline shows right now (reads the settings, never the disk)
---@return string text, boolean near
function M.statusline()
  local cfg = require("core.settings").agent.budget
  return M.chip((M.session()), cfg.enabled and cfg.session_usd or nil, cfg.warn_ratio)
end

return M
