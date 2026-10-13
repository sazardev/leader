-- ── Registro de acciones DDD ─────────────────────────────────────────────────
-- Mismo contrato que agent/actions (ver allí), en un registro APARTE: son otra función, con su menú
-- (<leader>aD) y su contexto propio (`ddd`). Se ejecutan con el mismo pipeline: misma experiencia
-- (diff en línea, hallazgos, ventana, historial y coste).
local M = {}

local NAMES = { "implement", "review", "fix", "missing", "ask" }

---@type table<string, table>
local cache = {}

---@param name string
---@return table
function M.get(name)
  if not cache[name] then
    local action = require("agent.ddd.actions." .. name)
    action.short = name
    action.name = "ddd_" .. name -- el historial y el informe de gasto los distinguen de los normales
    cache[name] = action
  end
  return cache[name]
end

---@return table[]
function M.list()
  return vim.tbl_map(M.get, NAMES)
end

return M
