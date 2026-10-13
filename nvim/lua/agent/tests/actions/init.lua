-- ── Registro de acciones de PRUEBAS (<leader>aT) ─────────────────────────────
-- Mismo contrato y pipeline que agent/actions, más los ganchos que el pipeline reconoce:
--   retarget(subject)   el resultado va al archivo de pruebas, no a la función (agent/tests/target.lua)
--   merge(code, target) el modelo devuelve solo lo nuevo; se une al final del archivo
--   reveal              abre el destino a un lado para aceptar/rechazar allí
--   prepare(target, cb) trabajo previo SIN modelo (correr la prueba); si no hay nada que pedir, 0 tokens
local M = {}

local NAMES = { "write", "mock", "fix" }

---@type table<string, table>
local cache = {}

---@param name string
---@return table
function M.get(name)
  if not cache[name] then
    local action = require("agent.tests.actions." .. name)
    action.short = name
    action.name = "test_" .. name
    cache[name] = action
  end
  return cache[name]
end

---@return table[]
function M.list()
  return vim.tbl_map(M.get, NAMES)
end

return M
