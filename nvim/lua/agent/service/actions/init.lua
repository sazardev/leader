-- ── Registro de acciones del nivel SERVICE ───────────────────────────────────
-- Servicios de aplicación / casos de uso: orquestan el dominio y llaman a los puertos. Mismo contrato y mismo pipeline
-- que agent/actions; el contexto propio del nivel es `ports` (las interfaces que el servicio puede llamar).
local M = {}

local NAMES = { "implement", "review" }

---@type table<string, table>
local cache = {}

---@param name string
---@return table
function M.get(name)
  if not cache[name] then
    local action = require("agent.service.actions." .. name)
    action.short = name
    action.name = "service_" .. name
    cache[name] = action
  end
  return cache[name]
end

---@return table[]
function M.list()
  return vim.tbl_map(M.get, NAMES)
end

return M
