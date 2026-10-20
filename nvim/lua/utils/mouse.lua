-- ── Hover and click for the config's own windows ────────────────────────────
-- Menus, pickers, modals and the start screen answer the mouse through here.
-- Clicks work wherever 'mouse' is on (a terminal too); hover needs the pointer's
-- moves, which Neovim only reports with 'mousemoveevent' and only the desktop app
-- sends (gui/mouse.lua). A window that wants hover marks its buffer with
-- `mouse.on(buf, …)`: the option follows the focused buffer (`sync`), so
-- anywhere else a key sequence that waits (which-key's leader menu, an operator)
-- never gets a <MouseMove> in the middle. Handlers receive
-- `vim.fn.getmousepos()`: winid, line, column (1-based) under the pointer.
local M = {}

--- Turns 'mousemoveevent' on while a buffer that asked for hover is focused (only inside the app).
function M.sync()
  local want = vim.g.leader_gui and vim.b.leader_hover == true or false
  if vim.o.mousemoveevent ~= want then
    vim.o.mousemoveevent = want
  end
end

---@class GuiMouseHandlers
---@field move fun(pos: table)?   the pointer moved to another cell
---@field click fun(pos: table)?  the left button was released
---@field press fun(pos: table)?  the left button went down (replaces Neovim's own: the focus does not move)
---@field modes string[]?         default { "n" } (Telescope's prompt is in insert mode)

--- Hover and click handlers for a buffer.
---@param buf integer
---@param h GuiMouseHandlers
function M.on(buf, h)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.b[buf].leader_hover = true
  local modes = h.modes or { "n" }
  local function map(lhs, fn, desc)
    vim.keymap.set(modes, lhs, function()
      fn(vim.fn.getmousepos())
    end, { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  if h.move then
    map("<MouseMove>", h.move, "Mouse hover")
  end
  if h.press then
    map("<LeftMouse>", h.press, "Mouse press")
  end
  if h.click then
    map("<LeftRelease>", h.click, "Mouse click")
  end
  if vim.api.nvim_get_current_buf() == buf then
    M.sync()
  end
end

--- Puts the cursor on `line` of `win` when it is a row the user can choose (`ok(line)`), and says if it moved.
---@param win integer
---@param line integer
---@param ok (fun(line: integer): boolean)?
---@return boolean
function M.follow(win, line, ok)
  if not vim.api.nvim_win_is_valid(win) or line < 1 then
    return false
  end
  if ok and not ok(line) then
    return false
  end
  local cur = vim.api.nvim_win_get_cursor(win)[1]
  if cur == line then
    return false
  end
  -- the pointer only points: the row under it is selected where it is, the window never scrolls for it. With the
  -- config's scrolloff a row near an edge would scroll the list, bring a new row under the still pointer, select
  -- that one and scroll again (the list running away from the mouse). Wheel and keys still scroll.
  vim.wo[win].scrolloff = 0
  local top = vim.fn.line("w0", win)
  pcall(vim.api.nvim_win_set_cursor, win, { line, 0 })
  if vim.fn.line("w0", win) ~= top then
    pcall(vim.api.nvim_win_call, win, function()
      vim.fn.winrestview { topline = top }
    end)
  end
  return true
end

--- Clickable chips on a line (" y Delete ", " ⏎ open "): their columns, from the segments that drew them.
---@param segments { [1]: string, [2]: string? }[]
---@param is_chip fun(group: string?): boolean
---@return { from: integer, to: integer, key: string, group: string }[] byte columns, 0-based, `to` exclusive
function M.chips(segments, is_chip)
  local out, col = {}, 0
  for _, seg in ipairs(segments) do
    local text, group = seg[1], seg[2]
    if is_chip(group) then
      local key = vim.trim(text):match "^(%S+)"
      if key then
        out[#out + 1] = { from = col, to = col + #text, key = key, group = group }
      end
    end
    col = col + #text
  end
  return out
end

--- What a chip's word means as keys: "Enter"/"⏎" → <CR>, "Esc" → <Esc>, "Tab" → <Tab>, "Space" → <Space>, others as typed.
---@param word string
---@return string
function M.keys(word)
  local named = { ["⏎"] = "<CR>", Enter = "<CR>", Esc = "<Esc>", Tab = "<Tab>", Space = "<Space>", ["⌫"] = "<BS>" }
  return named[word] or word
end

return M
