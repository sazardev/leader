-- ── Instruction recall ───────────────────────────────────────────────────────
-- What you typed in each action, to reuse with ↑/↓ in the inline field
-- (not to be confused with runs/: the run history with prompt, response and cost).
-- Persistent (agent/state), most recent first, no consecutive duplicates.
local state = require "agent.state"

local M = {}

local MAX = 30

---@param key string action ("implement", "ask"...)
---@return string[]
function M.list(key)
  return (state.get "prompt_history" or {})[key] or {}
end

---@param key string
---@param text string
function M.push(key, text)
  local all = state.get "prompt_history" or {}
  local list = vim.tbl_filter(function(t)
    return t ~= text
  end, all[key] or {})
  table.insert(list, 1, text)
  all[key] = vim.list_slice(list, 1, MAX)
  state.set("prompt_history", all)
end

return M
