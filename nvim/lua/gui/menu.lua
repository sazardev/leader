-- ── Desktop app: dropdown menus ──────────────────────────────────────────────
-- The app bar's menus (Leader's N = the app menu, the project's name = the
-- projects menu), opened right under their button: a flat block like the modals
-- (utils/modal.lua), one item per row with its key on the right, separators
-- between groups, submenus (▸) that open beside their item. j/k or the arrows
-- move (separators are skipped), Enter, l or a click runs or opens the submenu,
-- h goes back to the parent, Esc/q or leaving every menu closes them all. With the
-- mouse (utils/mouse.lua): the item under the pointer lights up, one with ▸ opens
-- its submenu as you pass over it (like Zed's), a click runs it.
-- An item can run a function or type the config's own keys (`keys`): then its
-- hint is those keys, written for people (Space f f, Ctrl+Shift+R).
-- Colors: GuiMenu* in ui/flat/groups.lua.
local M = {}

local NS = vim.api.nvim_create_namespace "GuiMenu"

---@class GuiMenuItem
---@field label string?
---@field hint string?    the key that does the same, shown dimmed on the right (default: from `keys`)
---@field keys string?    keys to type (the config's mapping runs, e.g. "<leader>fw")
---@field detail string?  a second, dimmed column (a project's path)
---@field current boolean? marked with a dot (the project you are in)
---@field run fun()?
---@field items GuiMenuItem[]? a submenu
---@field sep boolean?    a separator line
---@field when (fun(): boolean)? shown only when it returns true
---@field preview fun()? runs while the item is under the cursor or the pointer (a theme): `opts.revert` undoes it

---@type { win: integer, buf: integer, col: integer, row: integer, width: integer, items: GuiMenuItem[], parent: integer?, enter: fun(), sub: fun(row: integer, focus: boolean) }[] open menus, root first
local stack = {}
local guicursor ---@type string? the cursor shape while no menu was open
local revert ---@type fun()? undoes the previews when the menus close without a choice
local preview_timer = vim.uv.new_timer()

---@param it GuiMenuItem?
local function preview(it)
  preview_timer:stop()
  if it and it.preview then
    -- after a short pause: passing over items with the arrows does not repaint each one
    preview_timer:start(90, 0, vim.schedule_wrap(it.preview))
  end
end

--- "<leader>fw" → "Space f w", "<C-S-r>" → "Ctrl+Shift+R", "<M-i>" → "Alt+I"
---@param keys string
---@return string
function M.describe(keys)
  local parts = {}
  local i = 1
  while i <= #keys do
    local special = keys:match("^<[^>]+>", i)
    if special then
      local name = special:sub(2, -2)
      local lower = name:lower()
      if lower == "leader" or lower == "space" then
        parts[#parts + 1] = "Space"
      elseif lower == "cr" then
        parts[#parts + 1] = "Enter"
      else
        local mods, key = {}, name
        while key:match "^[CMSAD]%-" do
          local m = key:sub(1, 1)
          mods[#mods + 1] = ({ C = "Ctrl", M = "Alt", A = "Alt", S = "Shift", D = "Super" })[m]
          key = key:sub(3)
        end
        key = #key == 1 and key:upper() or key
        mods[#mods + 1] = key
        parts[#parts + 1] = table.concat(mods, "+")
      end
      i = i + #special
    else
      parts[#parts + 1] = keys:sub(i, i)
      i = i + 1
    end
  end
  return table.concat(parts, " ")
end

---@param s string
---@param w integer
local function pad(s, w)
  return s .. string.rep(" ", math.max(w - vim.fn.strdisplaywidth(s), 0))
end

---@param items GuiMenuItem[]
---@return GuiMenuItem[] the ones to show (their `when` holds), separators never doubled nor at the ends
function M.visible(items)
  local out = {}
  for _, it in ipairs(items) do
    if not it.when or it.when() then
      if not (it.sep and (#out == 0 or out[#out].sep)) then
        out[#out + 1] = it
      end
    end
  end
  while #out > 0 and out[#out].sep do
    out[#out] = nil
  end
  return out
end

---@param it GuiMenuItem
local function hint_of(it)
  if it.items then
    return "▸"
  end
  return it.hint or (it.keys and M.describe(it.keys)) or ""
end

--- The rows: text and the highlights to paint on them (pure, for the tests).
---@param items GuiMenuItem[] already filtered by `visible`
---@return string[] lines, table[] marks { row, col_start, col_end, group }, integer width
function M.render(items)
  local label_w, detail_w, hint_w = 0, 0, 0
  for _, it in ipairs(items) do
    if not it.sep then
      label_w = math.max(label_w, vim.fn.strdisplaywidth(it.label or ""))
      detail_w = math.max(detail_w, vim.fn.strdisplaywidth(it.detail or ""))
      hint_w = math.max(hint_w, vim.fn.strdisplaywidth(hint_of(it)))
    end
  end
  local width = 3 + label_w + (detail_w > 0 and detail_w + 3 or 0) + (hint_w > 0 and hint_w + 4 or 0) + 1
  width = math.max(width, 26)
  local lines, marks = {}, {}
  for i, it in ipairs(items) do
    if it.sep then
      lines[i] = " " .. string.rep("─", width - 2) .. " "
      marks[#marks + 1] = { i - 1, 0, #lines[i], "GuiMenuSep" }
    else
      local dot = it.current and "● " or "  "
      local text = " " .. dot .. pad(it.label or "", label_w)
      marks[#marks + 1] = { i - 1, 1, 1 + #dot, "GuiMenuMark" }
      if detail_w > 0 then
        local start = #text + 3
        text = text .. "   " .. pad(it.detail or "", detail_w)
        marks[#marks + 1] = { i - 1, start, #text, "GuiMenuDetail" }
      end
      local hint = hint_of(it)
      if hint_w > 0 then
        local gap = width - vim.fn.strdisplaywidth(text) - vim.fn.strdisplaywidth(hint) - 1
        text = text .. string.rep(" ", math.max(gap, 1))
        marks[#marks + 1] = { i - 1, #text, #text + #hint, it.items and "GuiMenuMark" or "GuiMenuHint" }
        text = text .. hint .. " "
      end
      lines[i] = text
    end
  end
  return lines, marks, width
end

--- Closes the menus above `level` (0 = all of them).
---@param level integer?
function M.close(level)
  level = level or 0
  while #stack > level do
    local top = table.remove(stack)
    if vim.api.nvim_win_is_valid(top.win) then
      pcall(vim.api.nvim_win_close, top.win, true)
    end
  end
  if #stack == 0 and guicursor then
    vim.o.guicursor = guicursor
    guicursor = nil
  end
  if #stack == 0 and revert then
    preview_timer:stop()
    local undo = revert
    revert = nil
    vim.schedule(undo)
  end
  if stack[#stack] and vim.api.nvim_win_is_valid(stack[#stack].win) then
    pcall(vim.api.nvim_set_current_win, stack[#stack].win)
  end
end

---@param it GuiMenuItem
local function activate(it)
  revert = nil -- a choice keeps what the previews showed
  if it.run then
    return it.run()
  end
  if it.keys then
    vim.api.nvim_feedkeys(vim.keycode(it.keys), "m", false)
  end
end

local open_level

--- Opens a menu at `level` (1 = the root), closing anything deeper.
---@param items GuiMenuItem[]
---@param level integer
---@param col integer
---@param row integer
---@param parent integer? the parent's row this submenu belongs to
---@param focus boolean? false = opened by hovering its item (the parent keeps the keyboard)
open_level = function(items, level, col, row, parent, focus)
  focus = focus ~= false
  M.close(level - 1)
  items = M.visible(items)
  local lines, marks, width = M.render(items)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(buf, NS, m[1], m[2], { end_col = m[3], hl_group = m[4] })
  end
  col = math.max(math.min(col, vim.o.columns - width - 2), 0)
  row = math.max(math.min(row, vim.o.lines - #lines - 4), 0)
  local win = vim.api.nvim_open_win(buf, focus, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = math.min(#lines, vim.o.lines - 4),
    style = "minimal",
    border = require("ui.flat").border(),
    zindex = 120 + level,
  })
  stack[level] = { win = win, buf = buf, col = col, row = row, width = width, items = items, parent = parent }
  vim.wo[win].winhighlight = "Normal:GuiMenu,EndOfBuffer:GuiMenu,CursorLine:GuiMenuSel"
  vim.wo[win].cursorline = true
  vim.wo[win].cursorlineopt = "line" -- the config's own is "number": the chosen row must light up whole
  if not guicursor then
    -- no cursor block over the menus (like the start screen: a cursor highlight with blend 100)
    guicursor = vim.o.guicursor
    vim.o.guicursor = "a:NvStartCursor"
  end
  pcall(function()
    require("ui.flat.motion").enter { win }
  end)

  local function selectable(r)
    return items[r] and not items[r].sep
  end
  local function move(delta)
    local r = vim.api.nvim_win_get_cursor(win)[1]
    repeat
      r = r + delta
    until selectable(r) or r < 1 or r > #items
    if selectable(r) then
      vim.api.nvim_win_set_cursor(win, { r, 0 })
      preview(items[r])
    end
  end
  local function enter()
    local r = vim.api.nvim_win_get_cursor(win)[1]
    local it = items[r]
    if not it or it.sep then
      return
    end
    if it.items then
      -- beside this menu, level with its item (the block's padding is one cell on each side)
      return open_level(it.items, level + 1, col + width + 2, row + r - 1, r, true)
    end
    revert = nil
    M.close()
    vim.schedule(function()
      activate(it)
    end)
  end
  stack[level].enter = enter
  stack[level].sub = function(r, keyboard)
    local it = items[r]
    if it and it.items then
      open_level(it.items, level + 1, col + width + 2, row + r - 1, r, keyboard)
    end
  end
  for r = 1, #items do
    if selectable(r) then
      vim.api.nvim_win_set_cursor(win, { r, 0 })
      break
    end
  end

  -- the mouse: every open menu answers the pointer, whichever has the keyboard
  local function under(pos)
    for lvl, s in ipairs(stack) do
      if s.win == pos.winid then
        return lvl, s
      end
    end
  end
  require("utils.mouse").on(buf, {
    move = function(pos)
      local lvl, s = under(pos)
      local it = s and s.items[pos.line]
      if not it or it.sep then
        return
      end
      if vim.api.nvim_win_get_cursor(s.win)[1] ~= pos.line then
        pcall(vim.api.nvim_win_set_cursor, s.win, { pos.line, 0 })
        preview(it)
      end
      if it.items then
        if not (stack[lvl + 1] and stack[lvl + 1].parent == pos.line) then
          s.sub(pos.line, false)
        end
      elseif #stack > lvl then
        M.close(lvl)
      end
    end,
    click = function(pos)
      local _, s = under(pos)
      local it = s and s.items[pos.line]
      if not it or it.sep then
        return
      end
      pcall(vim.api.nvim_set_current_win, s.win)
      pcall(vim.api.nvim_win_set_cursor, s.win, { pos.line, 0 })
      s.enter()
    end,
  })

  local map = function(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, desc = "Menu item" })
  end
  for _, k in ipairs { "j", "<Down>", "<Tab>" } do
    map(k, function()
      move(1)
    end)
  end
  for _, k in ipairs { "k", "<Up>", "<S-Tab>" } do
    map(k, function()
      move(-1)
    end)
  end
  for _, k in ipairs { "<CR>", "l", "<Right>" } do
    map(k, enter)
  end
  for _, k in ipairs { "h", "<Left>" } do
    map(k, function()
      if level > 1 then
        M.close(level - 1)
      else
        M.close()
      end
    end)
  end
  for _, k in ipairs { "<Esc>", "q", "<C-c>" } do
    map(k, function()
      M.close()
    end)
  end
  -- focus left every menu (a click on the editor, another window): they all close
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    callback = function()
      vim.schedule(function()
        local cur = vim.api.nvim_get_current_win()
        for _, s in ipairs(stack) do
          if s.win == cur then
            return
          end
        end
        M.close()
      end)
    end,
  })
end

---@param items GuiMenuItem[]
---@param opts? { col: integer?, revert: fun()? } `revert` runs when the menus close without a choice (undo previews)
function M.open(items, opts)
  opts = opts or {}
  M.close()
  open_level(items, 1, opts.col or 0, 0)
  revert = opts.revert
end

--- Every item that does something, with the path of menus to it ("File › Save"), for the command palette.
---@param items GuiMenuItem[]
---@param prefix string?
---@return { path: string, item: GuiMenuItem }[]
function M.flatten(items, prefix)
  local out = {}
  for _, it in ipairs(M.visible(items)) do
    if not it.sep then
      local path = prefix and (prefix .. " › " .. it.label) or it.label
      if it.items then
        vim.list_extend(out, M.flatten(it.items, path))
      elseif it.run or it.keys then
        out[#out + 1] = { path = path, item = it }
      end
    end
  end
  return out
end

M.activate = activate

return M
