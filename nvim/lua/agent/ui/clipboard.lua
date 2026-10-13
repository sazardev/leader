-- ── Copiar al portapapeles ───────────────────────────────────────────────────
-- Un solo lugar para todas las acciones de "copiar": registro del sistema (+) y el sin nombre ("),
-- con el aviso del tamaño copiado.
local log = require "utils.log"

local M = {}

---@param text string
---@param what string qué se copió ("run", "prompt"...)
function M.copy(text, what)
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  log.info(("Agent: copied %s (%.1f KB)"):format(what, #text / 1024))
end

return M
