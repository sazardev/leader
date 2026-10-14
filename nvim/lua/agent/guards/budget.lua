-- Guard: the spend budget (agent/budget.lua) applied to a request, reading the history and the settings.
local budget = require "agent.budget"
local settings = require("core.settings").agent

local M = {}

local SESSION_START = os.time()

---@return table[]
local function history()
  local ok, runs = pcall(function()
    return require("agent.runs.store").read()
  end)
  return ok and runs or {}
end

--- What `budget.check` needs besides the request: the history, the clock and when this session began
---@return { runs: table[], now: integer, session_start: integer }
function M.context()
  return { runs = history(), now = os.time(), session_start = SESSION_START }
end

---@param req table
---@return { level: string, title: string, lines: table }?
function M.check(req)
  local cfg = settings.budget
  if not cfg.enabled then
    return nil
  end
  local verdict = budget.check(req, cfg, M.context())
  if verdict.level == "ok" then
    return nil
  end
  -- what the user already confirmed (a batch asked once for all of it) is not asked again, but a cap still stops it
  if req.preapproved and verdict.level == "confirm" then
    return nil
  end
  local hl = require("utils.modal").hl
  local lines = {
    { { verdict.level == "block" and "Budget reached" or "This one is bigger than usual", hl.warn } },
    "",
    { { ("%s · %s"):format(req.action, budget.describe(verdict)) } },
  }
  for _, reason in ipairs(verdict.reasons) do
    lines[#lines + 1] = { { "  " .. reason, hl.muted } }
  end
  return { level = verdict.level, title = "Agent budget", message = verdict.reasons[1], lines = lines }
end

return M
