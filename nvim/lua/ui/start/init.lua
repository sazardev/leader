-- ── Start screen ─────────────────────────────────────────────────────────────
-- Replaces NvChad's nvdash with the landing page's start screen: art, repo, user and a column of buttons you move
-- through (j/k, arrows, Tab), activate (Enter, click) or jump to with their own shortcut (ff, fo, fw, th, ch, ca, rs).
-- `layout.lua` computes the screen (pure, tested); this file owns the buffer, the keys and the events.
local layout = require "ui.start.layout"

local M = {}

local NS = vim.api.nvim_create_namespace "NvStart"
local state = { buf = nil, win = nil, sel = 1, actions = {}, rows = {}, guicursor = nil }

---@return boolean
local function alive()
  return state.buf ~= nil
    and vim.api.nvim_buf_is_valid(state.buf)
    and state.win ~= nil
    and vim.api.nvim_win_is_valid(state.win)
    and vim.api.nvim_win_get_buf(state.win) == state.buf
end

function M.render()
  if not alive() then
    return
  end
  local info = require("utils.git").info()
  local repo = info.repo ~= "" and (info.branch ~= "" and ("%s (%s)"):format(info.repo, info.branch) or info.repo)
    or nil
  local lines, spans, rows = layout.compute {
    width = vim.api.nvim_win_get_width(state.win),
    height = vim.api.nvim_win_get_height(state.win),
    art = require("ui.arts").lines(),
    repo = repo,
    user = info.user,
    actions = state.actions,
    sel = state.sel,
  }
  state.rows = rows
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(state.buf, NS, 0, -1)
  for _, s in ipairs(spans) do
    vim.api.nvim_buf_set_extmark(
      state.buf,
      NS,
      s.row,
      s.col,
      { end_col = s.end_col, hl_group = s.hl, priority = 100 + (s.hl:find "Key" and 1 or 0) }
    )
  end
  pcall(vim.api.nvim_win_set_cursor, state.win, { (rows[state.sel] or 0) + 1, 0 })
end

---@param delta integer
local function move(delta)
  state.sel = (state.sel - 1 + delta) % #state.actions + 1
  M.render()
end

---@param index integer
local function activate(index)
  local action = state.actions[index]
  if not action then
    return
  end
  local cmd = action.cmd:gsub("^:", "")
  vim.cmd(cmd)
end

local function hide_cursor()
  if not state.guicursor then
    state.guicursor = vim.o.guicursor
  end
  vim.o.guicursor = "a:NvStartCursor"
end

local function restore_cursor()
  if state.guicursor then
    vim.o.guicursor = state.guicursor
    state.guicursor = nil
  end
end

local function bind(buf)
  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = false, silent = true })
  end
  for _, lhs in ipairs { "j", "<Down>", "<C-n>", "<Tab>" } do
    map(lhs, function()
      move(1)
    end)
  end
  for _, lhs in ipairs { "k", "<Up>", "<C-p>", "<S-Tab>" } do
    map(lhs, function()
      move(-1)
    end)
  end
  map("<CR>", function()
    activate(state.sel)
  end)
  map("<LeftMouse>", function()
    local pos = vim.fn.getmousepos()
    for i, row in ipairs(state.rows) do
      if row + 1 == pos.line then
        state.sel = i
        M.render()
        return activate(i)
      end
    end
  end)
  for i, action in ipairs(state.actions) do
    map(action.key, function()
      activate(i)
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

--- Shows the start screen in the current window
function M.open()
  ensure_groups()
  state.actions = require("ui.dashboard").actions()
  state.sel = 1
  local buf = vim.api.nvim_create_buf(false, true)
  state.buf, state.win = buf, vim.api.nvim_get_current_win()
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "nvdash" -- what the rest of the config (close, illuminate…) already recognizes
  vim.api.nvim_win_set_buf(state.win, buf)
  local wo = vim.wo[state.win]
  wo.number, wo.relativenumber, wo.signcolumn, wo.statuscolumn = false, false, "no", ""
  wo.cursorline, wo.list, wo.wrap, wo.foldenable, wo.colorcolumn = false, false, false, false, ""
  wo.winhighlight = "Normal:NvStartNormal,NormalNC:NvStartNormal,EndOfBuffer:NvStartNormal"
  bind(buf)
  hide_cursor()

  local group = vim.api.nvim_create_augroup("NvStart", { clear = true })
  vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, { group = group, callback = vim.schedule_wrap(M.render) })
  vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
    group = group,
    callback = function()
      if vim.api.nvim_get_current_buf() == state.buf then
        hide_cursor()
      else
        restore_cursor()
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufLeave", "BufWipeout" }, { group = group, buffer = buf, callback = restore_cursor })
  M.render()
end

--- Same screen after changing the art (ui/arts)
function M.redraw()
  M.render()
end

--- At startup: no file, no stdin, an empty buffer
function M.setup()
  vim.api.nvim_create_user_command("Nvdash", M.open, { force = true, desc = "Show the start screen" })
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
