-- ── Registro de presentadores ────────────────────────────────────────────────
-- Un presentador decide qué hace el resultado en el editor. Contrato:
--   stream(job)          (opcional) texto parcial en job.partial, mientras llega
--   done(job, result)    resultado final; devuelve (opcional) un resumen corto
--   release(job)         (opcional) cancelación/fallo: soltar lo que tenga montado
-- `action.output` elige el presentador. Añadir uno: archivo + NAMES.
local M = {}

local NAMES = { "replace", "findings", "text" }

---@type table<string, table>
local cache = {}

---@param kind string
---@return table
function M.get(kind)
  if not vim.tbl_contains(NAMES, kind) then
    error("agent: presentador desconocido '" .. tostring(kind) .. "'")
  end
  if not cache[kind] then
    cache[kind] = require("agent.output." .. kind)
  end
  return cache[kind]
end

return M
