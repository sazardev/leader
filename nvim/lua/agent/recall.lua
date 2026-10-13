-- ── Recuerdo de instrucciones ────────────────────────────────────────────────
-- Lo que escribiste en cada acción, para volver a usarlo con ↑/↓ en el campo inline
-- (no confundir con runs/: el historial de ejecuciones con prompt, respuesta y coste).
-- Persistente (agent/state), más reciente primero, sin repetidos consecutivos.
local state = require "agent.state"

local M = {}

local MAX = 30

---@param key string acción ("implement", "ask"...)
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
