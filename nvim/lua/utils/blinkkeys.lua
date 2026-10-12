-- ── Acciones propias de las teclas de blink.cmp ──────────────────────────────
-- blink acepta funciones en su `keymap`, pero no tienen nombre: aquí se declaran con una
-- etiqueta legible (LABELS) que usa el generador del cheatsheet (utils/cheatsheet.lua).
local M = {}

---@type table<function, string>
M.LABELS = {}

---@param label string
---@param fn function
---@return function
local function named(label, fn)
  M.LABELS[fn] = label
  return fn
end

-- Con un `ErrX` a medio declarar: acepta el texto fantasma (Tab) o lo acepta + línea nueva (Enter)
M.goerrors_accept = named("accept Go `ErrX` ghost text", function()
  return require("utils.goerrors").accept()
end)

M.goerrors_accept_newline = named("accept Go `ErrX` ghost text + new line", function()
  return require("utils.goerrors").accept(true)
end)

-- Dentro de un snippet y SIN menú abierto (con menú, Tab elige sugerencia): salta de hueco
M.snippet_next = named("jump to next snippet placeholder (when no menu is open)", function(cmp)
  if cmp.snippet_active { direction = 1 } then
    cmp.hide()
    return cmp.snippet_forward()
  end
end)

M.snippet_prev = named("jump to previous snippet placeholder (when no menu is open)", function(cmp)
  if cmp.snippet_active { direction = -1 } then
    cmp.hide()
    return cmp.snippet_backward()
  end
end)

return M
