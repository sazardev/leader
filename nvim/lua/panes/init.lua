-- ── Panes: real Neovim windows that open on the start screen ──────────────────
-- A pane is not a plugin: it is a split. `Alt+V` / `Alt+H` open one (right / below) with the start screen in it, so `ff`
-- (Telescope), `fo` (recent files) or any other button opens the chosen file in THAT pane and not in another. Native
-- `Ctrl+h/j/k/l` moves between panes; the arrows resize the current one; `<leader>V` has the rest (list, close, zoom…).
--
-- The dashboard is per pane (ui/start keeps one instance per window), so several start screens can be open at once.
local settings = require "core.settings"
local log = require "utils.log"

local M = {}

---@param win integer
---@return boolean
local function normal(win)
  return vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == ""
end

--- The current window, or the largest normal one when the cursor is in a float (a chat, a picker, a hover).
---@return integer
local function editing_window()
  local win = vim.api.nvim_get_current_win()
  if normal(win) then
    return win
  end
  local best, area
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if normal(w) then
      local a = vim.api.nvim_win_get_width(w) * vim.api.nvim_win_get_height(w)
      if not area or a > area then
        best, area = w, a
      end
    end
  end
  return best or win
end

--- Leaves insert/terminal mode before changing the layout (a split is not allowed from insert with a count, and
--- opening one with the cursor in a running terminal would leave the keys going to the shell).
local function leave_input()
  local mode = vim.fn.mode()
  if mode:sub(1, 1) == "i" or mode == "t" then
    pcall(vim.cmd, "stopinsert")
  end
end

--- Opens a pane in `direction` ("right", "left", "below" or "above") and shows the start screen in it.
--- `settings.panes.dashboard = false` leaves the same buffer in the new pane, like a plain split.
---@param direction "right"|"left"|"below"|"above"?
---@return integer? the new window
function M.open(direction)
  local dir = direction or "right"
  local cmd = ({
    right = "rightbelow vsplit",
    left = "aboveleft vsplit",
    below = "belowright split",
    above = "aboveleft split",
  })[dir]
  if not cmd then
    log.warn(("Pane: unknown direction '%s'"):format(tostring(dir)))
    return nil
  end
  leave_input()
  local base = editing_window()
  if not normal(base) then
    log.warn "Pane: there is no window to split"
    return nil
  end
  vim.api.nvim_set_current_win(base)
  local ok, err = pcall(vim.cmd, cmd)
  if not ok then
    log.warn("Pane: " .. tostring(err))
    return nil
  end
  local win = vim.api.nvim_get_current_win()
  if settings.panes.dashboard ~= false then
    require("ui.start").open()
  end
  return win
end

--- The start screen in the current pane (the pane itself when it is already showing one).
function M.dashboard()
  leave_input()
  local base = editing_window()
  if not normal(base) then
    log.warn "Pane: there is no window for the dashboard"
    return nil
  end
  vim.api.nvim_set_current_win(base)
  return require("ui.start").open()
end

--- Number of normal (non floating) windows in this tab
---@return integer
local function normal_windows()
  local n = 0
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if normal(win) then
      n = n + 1
    end
  end
  return n
end

--- Closes the pane under the cursor (a float closes itself). The last one stays: there is nothing to go back to.
---@return boolean closed
function M.close()
  local win = vim.api.nvim_get_current_win()
  if not normal(win) then
    return pcall(vim.api.nvim_win_close, win, true)
  end
  if normal_windows() <= 1 then
    log.info "Pane: the last one stays"
    return false
  end
  local ok, err = pcall(vim.cmd, "close")
  if not ok then
    -- E37: the buffer has changes and no other window shows it
    log.warn(("Pane: %s"):format(tostring(err):gsub("^Vim%(%a+%):", ""):gsub("^%s+", "")))
    return false
  end
  return true
end

--- Resizes the current pane: left/narrower, right/wider, up/shorter, down/taller.
---@param direction "left"|"right"|"up"|"down"
---@param step integer? cells (settings.panes.resize_step by default)
---@return boolean resized
function M.resize(direction, step)
  local win = vim.api.nvim_get_current_win()
  if not normal(win) or normal_windows() <= 1 then
    return false
  end
  step = step or settings.panes.resize_step or 2
  local width, height = vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win)
  local ok
  if direction == "left" then
    ok = pcall(vim.api.nvim_win_set_width, win, math.max(1, width - step))
  elseif direction == "right" then
    ok = pcall(vim.api.nvim_win_set_width, win, width + step)
  elseif direction == "up" then
    ok = pcall(vim.api.nvim_win_set_height, win, math.max(1, height - step))
  elseif direction == "down" then
    ok = pcall(vim.api.nvim_win_set_height, win, height + step)
  else
    return false
  end
  return ok
end

--- Gives every pane the same size
function M.equal()
  pcall(vim.cmd, "wincmd =")
end

--- Rotates the panes
function M.rotate()
  pcall(vim.cmd, "wincmd r")
end

--- Swaps this pane with the next one
function M.swap()
  pcall(vim.cmd, "wincmd x")
end

--- Puts this pane alone on its own tab (the original layout is kept in the other tab). Press again to come back.
function M.zoom()
  local tab = vim.api.nvim_get_current_tabpage()
  if vim.t.leader_zoom_from then
    local from = vim.t.leader_zoom_from
    vim.t.leader_zoom_from = nil
    if vim.api.nvim_tabpage_is_valid(from) and #vim.api.nvim_list_tabpages() > 1 then
      pcall(vim.cmd, "tabclose")
    end
    return
  end
  leave_input()
  local ok = pcall(vim.cmd, "tab split")
  if not ok then
    return
  end
  vim.t.leader_zoom_from = tab
  -- the duplicated start screen belongs to the old window: this tab needs its own instance
  if vim.bo.filetype == "nvdash" then
    require("ui.start").open()
  end
end

--- One row of the pane picker (pure enough to test the labels)
---@param win integer
---@param current integer
---@return { label: string, desc: string, value: integer, current: boolean }
function M.item(win, current)
  local buf = vim.api.nvim_win_get_buf(win)
  local name = vim.api.nvim_buf_get_name(buf)
  local ft = vim.bo[buf].filetype
  local label
  if ft == "nvdash" then
    label = "Dashboard"
  elseif ft == "NvimTree" then
    label = "File tree"
  elseif vim.bo[buf].buftype == "terminal" then
    label = "Terminal"
  elseif name == "" then
    label = "[No Name]"
  else
    label = vim.fn.fnamemodify(name, ":t")
  end
  local desc = ("%dx%d · %s%s"):format(
    vim.api.nvim_win_get_width(win),
    vim.api.nvim_win_get_height(win),
    ft ~= "" and ft or "file",
    vim.bo[buf].modified and " · modified" or ""
  )
  return { label = label, desc = desc, value = win, current = win == current }
end

--- Lists the panes; Enter focuses the chosen one
function M.pick()
  local current = vim.api.nvim_get_current_win()
  local items = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if normal(win) then
      items[#items + 1] = M.item(win, current)
    end
  end
  if #items <= 1 then
    return log.info "Pane: there is only one"
  end
  require("tasks.picker").choose(items, { title = "Panes", hint = "Enter focus" }, function(win)
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
    end
  end)
end

function M.setup()
  local map = vim.keymap.set
  map({ "n", "t" }, "<A-v>", function()
    M.open "right"
  end, { desc = "Panes split right (start screen)" })
  map({ "n", "t" }, "<A-h>", function()
    M.open "below"
  end, { desc = "Panes split down (start screen)" })
  map("n", "<A-Left>", function()
    M.resize "left"
  end, { desc = "Panes narrower" })
  map("n", "<A-Right>", function()
    M.resize "right"
  end, { desc = "Panes wider" })
  map("n", "<A-Up>", function()
    M.resize "up"
  end, { desc = "Panes shorter" })
  map("n", "<A-Down>", function()
    M.resize "down"
  end, { desc = "Panes taller" })
  map("n", "<A-z>", M.zoom, { desc = "Panes zoom (toggle)" })
  map("n", "<A-q>", M.close, { desc = "Panes close" })
end

return M
