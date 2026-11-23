-- ── Python REPL: el comando de IPython ────────────────────────────────────────
-- La misma lógica que languages/actions/python.lua (uv run → ipython global) y
-- los mismos flags, para que las sesiones del workspace sean indistinguibles
-- del REPL de siempre. Un nombre distinto por sesión mantiene terminales aparte.
local M = {}

---@param root string?
---@return string?
function M.base(root)
  local py = require "utils.python"
  local r = root or py.root()
  if vim.fn.executable "uv" == 1 and py.uv_project(r) then
    return "uv run ipython"
  end
  if vim.fn.executable "ipython" == 1 then
    return "ipython"
  end
end

---@param root string?
---@return string?
function M.repl(root)
  local base = M.base(root)
  if not base then
    return
  end
  return base
    .. " --no-banner --no-confirm-exit"
    .. " --TerminalInteractiveShell.autosuggestions_provider=NavigableAutoSuggestFromHistory"
end

---@param session string
---@return string
function M.term_name(session)
  return "Python REPL [" .. session .. "]"
end

return M
