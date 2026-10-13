-- ── Custom actions for the blink.cmp keys ──────────────────────────────────
-- blink accepts functions in its `keymap`, but they have no name: here they are declared with a
-- readable label (LABELS) used by the cheatsheet generator (utils/cheatsheet.lua).
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

-- With a half-typed `ErrX`: accept the ghost text (Tab) or accept it + new line (Enter)
M.goerrors_accept = named("accept Go `ErrX` ghost text", function()
  return require("utils.goerrors").accept()
end)

M.goerrors_accept_newline = named("accept Go `ErrX` ghost text + new line", function()
  return require("utils.goerrors").accept(true)
end)

-- Inside a snippet and with NO menu open (with a menu, Tab picks a suggestion): jump to the next placeholder
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
