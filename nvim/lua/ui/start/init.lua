-- ── Start screen ─────────────────────────────────────────────────────────────
-- Replaces NvChad's nvdash with the landing page's start screen: art, repo, user and a column of buttons you move
-- through (j/k, arrows, Tab), activate (Enter, click) or jump to with their own shortcut (ff, fo, fw, th, ch, ca, rs).
-- `layout.lua` computes the screen (pure, tested); this file owns the buffers, the keys and the events.
--
-- ONE SCREEN PER PANE: Alt+V / Alt+H can open a dashboard in several windows, so every window has its own buffer,
-- selection, rows and saved options and the buffer-local keys only move the screen they belong to.
local layout = require "ui.start.layout"

local M = {}

local NS = vim.api.nvim_create_namespace "NvStart"

---@class StartInstance
---@field buf integer
---@field win integer
---@field sel integer
---@field actions { label: string, key: string, cmd: string }[]
---@field rows integer[]
---@field saved table<string, any>
local instances = {} ---@type table<integer, StartInstance>

-- window options the start screen changes: they are window-local, so they would stay on the window and the file opened
-- from the screen (ff, fo, Enter…) would come out without line numbers. A split of another start screen INHERITS those
-- local values, so in that case (the buffer is already nvdash) the GLOBAL value is saved instead: the new pane must get
-- a normal file window when a file replaces its dashboard.
local WINDOW_OPTIONS = {
  "number",
  "relativenumber",
  "signcolumn",
  "statuscolumn",
  "cursorline",
  "list",
  "wrap",
  "foldenable",
  "colorcolumn",
  "winhighlight",
}

---@param inst StartInstance?
---@return boolean
local function alive(inst)
  return inst ~= nil
    and inst.buf ~= nil
    and vim.api.nvim_buf_is_valid(inst.buf)
    and inst.win ~= nil
    and vim.api.nvim_win_is_valid(inst.win)
    and vim.api.nvim_win_get_buf(inst.win) == inst.buf
end

--- The start screen shown in `win` (the current window by default), or nil.
---@param win integer?
---@return StartInstance?
function M.instance(win)
  win = win or vim.api.nvim_get_current_win()
  for _, inst in pairs(instances) do
    if inst.win == win and alive(inst) then
      return inst
    end
  end
end

---@param inst StartInstance
function M.render(inst)
  inst = inst or M.instance()
  if not alive(inst) then
    return
  end
  local info = require("utils.git").info()
  local repo = info.repo ~= "" and (info.branch ~= "" and ("%s (%s)"):format(info.repo, info.branch) or info.repo)
    or nil
  local lines, spans, rows = layout.compute {
    width = vim.api.nvim_win_get_width(inst.win),
    height = vim.api.nvim_win_get_height(inst.win),
    art = require("ui.arts").lines(),
    repo = repo,
    user = info.user,
    actions = inst.actions,
    sel = inst.sel,
    edges = require("ui.flat").enabled(),
  }
  inst.rows = rows
  vim.bo[inst.buf].modifiable = true
  vim.api.nvim_buf_set_lines(inst.buf, 0, -1, false, lines)
  vim.bo[inst.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(inst.buf, NS, 0, -1)
  for _, s in ipairs(spans) do
    vim.api.nvim_buf_set_extmark(inst.buf, NS, s.row, s.col, {
      end_col = s.end_col,
      hl_group = s.hl,
      priority = 100 + (s.hl:find "Key" and 1 or 0),
    })
  end
  pcall(vim.api.nvim_win_set_cursor, inst.win, { (rows[inst.sel] or 0) + 1, 0 })
end

---@param inst StartInstance
---@param delta integer
local function move(inst, delta)
  inst.sel = (inst.sel - 1 + delta) % #inst.actions + 1
  M.render(inst)
end

--- Runs the button's command in ITS window, so `ff` (Telescope) opens the selected file in this pane and not in another.
---@param inst StartInstance
---@param index integer
local function activate(inst, index)
  local action = inst.actions[index]
  if not action or not alive(inst) then
    return
  end
  local cmd = action.cmd:gsub("^:", "")
  -- NOT nvim_win_call: Telescope (and anything that opens windows while the command runs) gets a broken layout inside
  -- it. Going to the pane first is enough: the buffer-local key only fires while that pane is the current one.
  vim.api.nvim_set_current_win(inst.win)
  vim.cmd(cmd)
end

---@param inst StartInstance
local function hide_cursor(inst)
  require("utils.cursor").hide(inst)
end

---@param inst StartInstance
local function restore_cursor(inst)
  require("utils.cursor").show(inst)
end

--- `vim.wo[win][name] = value` also changes the GLOBAL value of a window-local option (new splits then inherit the
--- start screen's hidden numbers). This only touches the window's local value.
---@param win integer
---@param name string
---@param value any
local function set_local(win, name, value)
  vim.api.nvim_set_option_value(name, value, { win = win, scope = "local" })
end

--- Gives the window its normal options back when the start screen really left it. BufWinLeave fires BEFORE the buffer
--- is removed, so the decision is made once the new buffer is in place; a window that still shows the start screen (a
--- split that only duplicated it) keeps its options.
---@param inst StartInstance
local function restore_window(inst)
  if not (inst.saved and inst.win) then
    return
  end
  vim.schedule(function()
    if not (inst.saved and inst.win and vim.api.nvim_win_is_valid(inst.win)) then
      return
    end
    local buf = vim.api.nvim_win_get_buf(inst.win)
    if buf == inst.buf or vim.bo[buf].filetype == "nvdash" then
      return
    end
    for name, value in pairs(inst.saved) do
      set_local(inst.win, name, value)
    end
    inst.saved = nil
  end)
end

---@param inst StartInstance
---@param buf integer
local function bind(inst, buf)
  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = false, silent = true })
  end
  for _, lhs in ipairs { "j", "<Down>", "<C-n>", "<Tab>" } do
    map(lhs, function()
      move(inst, 1)
    end)
  end
  for _, lhs in ipairs { "k", "<Up>", "<C-p>", "<S-Tab>" } do
    map(lhs, function()
      move(inst, -1)
    end)
  end
  map("<CR>", function()
    activate(inst, inst.sel)
  end)
  ---@return integer? the button under the pointer (its label row or the half cell under it)
  local function button_at(pos)
    for i, row in ipairs(inst.rows) do
      if row + 1 == pos.line or (row + 2 == pos.line and not vim.tbl_contains(inst.rows, row + 1)) then
        return i
      end
    end
  end
  map("<LeftMouse>", function()
    local i = button_at(vim.fn.getmousepos())
    if i then
      inst.sel = i
      M.render(inst)
      return activate(inst, i)
    end
  end)
  -- hover (the desktop app reports the pointer's moves): the button under it is the selected one
  require("utils.mouse").on(buf, {
    move = function(pos)
      local i = button_at(pos)
      if i and i ~= inst.sel then
        inst.sel = i
        M.render(inst)
      end
    end,
  })
  for i, action in ipairs(inst.actions) do
    map(action.key, function()
      activate(inst, i)
    end)
  end
end

--- Without the flat design its groups do not exist: borrow the editor's own colors
local function ensure_groups()
  if vim.fn.hlexists "NvStartSel" == 1 and next(vim.api.nvim_get_hl(0, { name = "NvStartSel" })) ~= nil then
    return
  end
  local links = {
    NvStartNormal = "Normal",
    NvStartArt = "Special",
    NvStartRepo = "WarningMsg",
    NvStartUser = "Comment",
    NvStartBtn = "Pmenu",
    NvStartBtnKey = "Comment",
    NvStartSel = "PmenuSel",
    NvStartSelKey = "PmenuSel",
  }
  for name, target in pairs(links) do
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
  end
  vim.api.nvim_set_hl(0, "NvStartCursor", { blend = 100, nocombine = true, default = true })
end

--- Shows the start screen in the current window. A window that already shows one is redrawn instead of duplicated.
---@return StartInstance
function M.open()
  ensure_groups()
  local win = vim.api.nvim_get_current_win()
  local existing = M.instance(win)
  if existing then
    existing.actions = require("ui.dashboard").actions()
    existing.sel = 1
    hide_cursor(existing)
    M.render(existing)
    return existing
  end

  local inst = {
    buf = vim.api.nvim_create_buf(false, true),
    win = win,
    sel = 1,
    actions = require("ui.dashboard").actions(),
    rows = {},
    saved = {},
  }
  local from_dashboard = vim.bo[vim.api.nvim_get_current_buf()].filetype == "nvdash"
  for _, name in ipairs(WINDOW_OPTIONS) do
    inst.saved[name] = from_dashboard and vim.go[name]
      or vim.api.nvim_get_option_value(name, { win = win, scope = "local" })
  end
  instances[inst.buf] = inst
  vim.bo[inst.buf].bufhidden = "wipe"
  vim.bo[inst.buf].swapfile = false
  vim.bo[inst.buf].filetype = "nvdash" -- what the rest of the config (close, illuminate…) already recognizes
  vim.api.nvim_win_set_buf(win, inst.buf)
  for name, value in pairs {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    statuscolumn = "",
    cursorline = false,
    list = false,
    wrap = false,
    foldenable = false,
    colorcolumn = "",
    winhighlight = "Normal:NvStartNormal,NormalNC:NvStartNormal,EndOfBuffer:NvStartNormal",
  } do
    set_local(win, name, value)
  end
  bind(inst, inst.buf)
  hide_cursor(inst)
  M.render(inst)
  return inst
end

--- Same screen in every pane after changing the art (ui/arts)
function M.redraw()
  for _, inst in pairs(instances) do
    if alive(inst) then
      M.render(inst)
    end
  end
end

--- At startup: no file, no stdin, an empty buffer
function M.setup()
  vim.api.nvim_create_user_command("Nvdash", M.open, { force = true, desc = "Show the start screen" })
  local group = vim.api.nvim_create_augroup("NvStart", { clear = true })
  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = group,
    callback = vim.schedule_wrap(function()
      M.redraw()
    end),
  })
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = group,
    callback = function()
      local inst = M.instance()
      if inst then
        hide_cursor(inst)
      end
    end,
  })
  -- one owner per pane: leaving it gives the cursor back; entering another start screen hides it again
  vim.api.nvim_create_autocmd("BufLeave", {
    group = group,
    callback = function(args)
      local inst = instances[args.buf]
      if inst then
        restore_cursor(inst)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = group,
    callback = function(args)
      local inst = instances[args.buf]
      if inst then
        restore_window(inst)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(args)
      local inst = instances[args.buf]
      if inst then
        instances[args.buf] = nil
        restore_cursor(inst)
        restore_window(inst)
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimEnter", {
    group = vim.api.nvim_create_augroup("NvStartup", { clear = true }),
    once = true,
    callback = function()
      local empty = vim.api.nvim_buf_get_name(0) == ""
        and vim.api.nvim_buf_line_count(0) == 1
        and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == ""
      if vim.fn.argc() == 0 and empty and not vim.g.started_with_stdin and not vim.o.diff then
        M.open()
      end
    end,
  })
end

return M
