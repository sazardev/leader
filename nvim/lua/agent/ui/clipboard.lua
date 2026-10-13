-- ── Copy to clipboard ────────────────────────────────────────────────────────
-- A single place for all "copy" actions: the system register (+) and the unnamed one ("),
-- with a notice of the size copied.
local log = require "utils.log"

local M = {}

---@param text string
---@param what string what was copied ("run", "prompt"...)
function M.copy(text, what)
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  log.info(("Agent: copied %s (%.1f KB)"):format(what, #text / 1024))
end

return M
