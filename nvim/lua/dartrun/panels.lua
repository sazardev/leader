-- ── Everything a run puts on the screen, hidden with one key ─────────────────
-- The app's log (flutter-tools' bottom split), the debug panel (nvim-dap-view) and the widget outline. `hide` closes
-- the ones that are open; with none open, `toggle` shows the log (the one you look at most while the app runs).
local M = {}

local LOG = "__FLUTTER_DEV_LOG__"
local OUTLINE = "Flutter Outline"

---@param name string tail of the buffer name
---@return integer[] windows of the current tab showing it
local function windows(name)
  local out = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf_name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
    if buf_name:sub(-#name) == name then
      out[#out + 1] = win
    end
  end
  return out
end

local function dap_view_open()
  local state = package.loaded["dap-view.state"]
  return state ~= nil and state.winnr ~= nil and vim.api.nvim_win_is_valid(state.winnr)
end

--- Names of what is on screen now
---@return string[]
function M.open()
  local out = {}
  if #windows(LOG) > 0 then
    out[#out + 1] = "log"
  end
  if dap_view_open() then
    out[#out + 1] = "debug panel"
  end
  if #windows(OUTLINE) > 0 then
    out[#out + 1] = "outline"
  end
  return out
end

--- Closes what is open
---@return integer how many panels were closed
function M.hide()
  local open = M.open()
  for _, win in ipairs(windows(LOG)) do
    pcall(vim.api.nvim_win_close, win, true)
  end
  if dap_view_open() then
    pcall(require("dap-view").close)
  end
  for _, win in ipairs(windows(OUTLINE)) do
    pcall(vim.api.nvim_win_close, win, true)
  end
  return #open
end

--- Hides what is open; nothing open → the log
function M.toggle()
  if M.hide() == 0 then
    local ok, log = pcall(require, "flutter-tools.log")
    if ok then
      log.toggle()
    end
  end
end

return M
