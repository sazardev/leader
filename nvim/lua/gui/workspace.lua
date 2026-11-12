-- ── Desktop app: the workspace layer ────────────────────────────────────────
-- The Zed-shaped things that sit above a single buffer: the docks (file tree, chat/agent, terminal, problems), the
-- panes (real Neovim splits), quick open and focus mode. Every action here is safe to call from the app bar, a menu,
-- the command palette or a window shortcut: a missing plugin returns instead of throwing, so the editor never breaks.
-- The state is read lazily (no plugin is loaded just to draw an icon) and the pure bits are tested by scripts/test-gui.
local settings = require "core.settings"

local M = {}

--- A pcall that returns nil when the module/command is not here yet.
---@param fn fun(): any
---@return any
local function safe(fn)
  local ok, value = pcall(fn)
  return ok and value or nil
end

local function nvim_tree()
  return safe(function()
    return require "nvim-tree.api"
  end)
end

--- Filetypes that are docks/panels rather than editor panes (the tree, the chat, a terminal, problems, the outline…).
local PANELS = {
  NvimTree = true,
  aerial = true,
  Trouble = true,
  trouble = true,
  toggleterm = true,
  leaderchat = true,
  leaderchat_input = true,
  help = true,
  qf = true,
}

--- The largest normal window that edits a file (or the start screen): not a dock, not a float. The panes menu is
--- opened from the app bar, where the focused window may be the chat or the tree.
---@return integer?
local function editing_window()
  local best, area
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    local ft = vim.bo[buf].filetype
    if
      vim.api.nvim_win_get_config(win).relative == ""
      and not PANELS[ft]
      and (vim.bo[buf].buftype == "" or ft == "nvdash")
    then
      local a = vim.api.nvim_win_get_width(win) * vim.api.nvim_win_get_height(win)
      if not area or a > area then
        best, area = win, a
      end
    end
  end
  return best
end

--- Runs a pane action on the editor window, never on the chat/tree that happened to have the focus.
---@param fn fun()
local function on_editor(fn)
  local win = editing_window()
  if win then
    pcall(vim.api.nvim_set_current_win, win)
  end
  fn()
end

local function chat_window()
  return package.loaded["agent.chat.window"]
end

-- ── what is open (for the toolbar) ──────────────────────────────────────────

---@return boolean
function M.tree_open()
  if not (package.loaded["nvim-tree"] or package.loaded["nvim-tree.api"]) then
    return false
  end
  local api = nvim_tree()
  return (api and safe(function()
    return api.tree.is_visible()
  end)) or false
end

---@return boolean
function M.chat_open()
  local window = chat_window()
  return (window and safe(function()
    return window.is_open()
  end)) or false
end

--- Number of real (non floating) editor windows in this tab: docks and panels do not count, so opening the tree or
--- the chat does not light the panes tool.
---@return integer
function M.pane_count()
  local n = 0
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    local ft = vim.bo[buf].filetype
    if
      vim.api.nvim_win_get_config(win).relative == ""
      and not PANELS[ft]
      and (vim.bo[buf].buftype == "" or ft == "nvdash")
    then
      n = n + 1
    end
  end
  return n
end

---@return boolean
function M.panes_active()
  return M.pane_count() > 1
end

---@return boolean
function M.problems_open()
  if not package.loaded["trouble"] then
    return false
  end
  local api = safe(function()
    return require "trouble.api"
  end)
  return (api and safe(function()
    return api.is_open()
  end)) or false
end

---@return boolean
function M.terminal_open()
  if not package.loaded["toggleterm"] then
    return false
  end
  return (
    safe(function()
      for _, term in pairs(require("toggleterm.terminal").get_all()) do
        if term:is_open() then
          return true
        end
      end
      return false
    end)
  ) or false
end

---@return { tree: boolean, chat: boolean, panes: boolean, problems: boolean, terminal: boolean, focus: boolean }
function M.state()
  return {
    tree = M.tree_open(),
    chat = M.chat_open(),
    panes = M.panes_active(),
    problems = M.problems_open(),
    terminal = M.terminal_open(),
    focus = M.focus_active(),
  }
end

-- ── left / right / bottom docks ─────────────────────────────────────────────

--- Shows or hides the file tree. Opening it puts the keys in it (Zed's project panel).
function M.toggle_tree()
  local api = nvim_tree()
  if api then
    local ok = pcall(api.tree.toggle, { focus = true })
    if ok then
      return require("gui").update()
    end
  end
  pcall(vim.cmd, "NvimTreeToggle")
  require("gui").update()
end

--- Shows or hides the chat / agent panel. The chat keeps running when hidden; opening it again brings the session back.
function M.toggle_chat()
  pcall(function()
    require("agent.chat").open()
  end)
  require("gui").update()
end

--- The quick terminal pane (below the current pane, one shell per tab).
function M.toggle_terminal_pane()
  pcall(function()
    require("utils.terminal").pane()
  end)
  require("gui").update()
end

--- The floating terminal (the classic Alt-I).
function M.toggle_terminal()
  pcall(function()
    require("utils.terminal").focus()
  end)
  require("gui").update()
end

function M.toggle_problems()
  pcall(vim.cmd, "Trouble diagnostics toggle")
  require("gui").update()
end

function M.toggle_outline()
  pcall(vim.cmd, "AerialToggle")
  require("gui").update()
end

-- ── quick open ──────────────────────────────────────────────────────────────

--- Opens a file with Telescope (the same picker as <leader>ff), with a prompt that says so.
function M.quick_open()
  local builtin = safe(function()
    return require "telescope.builtin"
  end)
  if builtin then
    return builtin.find_files { prompt_title = "Open File" }
  end
  pcall(vim.cmd, "edit .")
end

function M.save_all()
  pcall(vim.cmd, "silent! wall")
end

-- ── panes ───────────────────────────────────────────────────────────────────

---@param direction "right"|"left"|"below"|"above"
function M.split(direction)
  pcall(function()
    require("panes").open(direction)
  end)
  require("gui").update()
end

---@param name "double"|"triple"|"main"|"quad"
function M.layout(name)
  pcall(function()
    require("panes").preset(name)
  end)
  require("gui").update()
end

---@param direction "left"|"right"|"up"|"down"
function M.focus_pane(direction)
  local key = ({ left = "h", right = "l", up = "k", down = "j" })[direction]
  if key then
    pcall(vim.cmd, "wincmd " .. key)
  end
end

function M.next_pane()
  pcall(vim.cmd, "wincmd w")
end

function M.previous_pane()
  pcall(vim.cmd, "wincmd W")
end

function M.zoom_pane()
  on_editor(function()
    pcall(function()
      require("panes").zoom()
    end)
  end)
end

function M.equal_panes()
  pcall(function()
    require("panes").equal()
  end)
end

function M.rotate_panes()
  on_editor(function()
    pcall(function()
      require("panes").rotate()
    end)
  end)
end

function M.swap_panes()
  on_editor(function()
    pcall(function()
      require("panes").swap()
    end)
  end)
end

function M.close_pane()
  on_editor(function()
    pcall(function()
      require("panes").close()
    end)
  end)
end

function M.close_other_panes()
  on_editor(function()
    pcall(function()
      require("panes").only()
    end)
  end)
end

function M.list_panes()
  pcall(function()
    require("panes").pick()
  end)
end

function M.dashboard()
  on_editor(function()
    pcall(function()
      require("panes").dashboard()
    end)
  end)
end

-- ── chat / agent options ────────────────────────────────────────────────────

--- Chat session if it was loaded (`nil` before the panel is opened).
---@return table?
function M.chat_session()
  local window = chat_window()
  return window and window.session or nil
end

function M.chat_new()
  pcall(function()
    require("agent.chat").new_session()
  end)
end

function M.chat_history()
  pcall(function()
    require("agent.chat").pick_session()
  end)
end

function M.chat_model()
  pcall(function()
    require("agent.chat").pick_model()
  end)
end

function M.chat_effort()
  pcall(function()
    require("agent.chat").pick_effort()
  end)
end

function M.chat_profile()
  pcall(function()
    require("agent.chat").pick_profile()
  end)
end

function M.chat_stop()
  pcall(function()
    require("agent.chat").stop()
  end)
end

function M.chat_clear()
  pcall(function()
    require("agent.chat").clear()
  end)
end

---@param view "mini"|"full"
function M.chat_view(view)
  pcall(function()
    require("agent.chat").set_view(view)
  end)
end

function M.chat_toggle_view()
  pcall(function()
    require("agent.chat").toggle_view()
  end)
end

function M.chat_collapse()
  pcall(function()
    require("agent.chat").toggle_collapse()
  end)
end

--- Toggles "a Write answer applies its complete files" through the settings panel's own item (saved).
function M.chat_toggle_apply()
  local prefs = require "prefs"
  local item = prefs.find "agent.chat.apply"
  if item then
    prefs.set(item, not prefs.value(item))
  end
end

function M.chat_help()
  pcall(function()
    require("agent.chat").help()
  end)
end

-- ── focus mode ──────────────────────────────────────────────────────────────

---@type { bar: boolean, statusline: integer }?
local focus_saved

---@return boolean
function M.focus_active()
  return focus_saved ~= nil
end

--- Hides the app bar and the statusline, leaving only the code (the frameless window is kept: the bar is hidden by
--- `gui.appbar.visible`, not by asking for system decorations). Calling it again restores exactly what was there.
---@param on boolean? nil = toggle
---@return boolean active
function M.focus(on)
  if on == false and focus_saved then
    settings.gui.appbar.visible = focus_saved.bar
    vim.o.laststatus = focus_saved.statusline
    focus_saved = nil
    require("gui").update()
    pcall(vim.cmd, "redraw")
    return false
  end
  if focus_saved then
    return true
  end
  if on == false then
    return false
  end
  local cfg = (settings.gui.workspace or {}).focus or {}
  focus_saved = { bar = settings.gui.appbar.visible ~= false, statusline = vim.o.laststatus }
  if cfg.bar ~= false then
    settings.gui.appbar.visible = false
  end
  if cfg.statusline ~= false then
    vim.o.laststatus = 0
  end
  require("gui").update()
  pcall(vim.cmd, "redraw")
  return true
end

--- The panes menu, shared by the app bar, the View menu and the window shortcut.
---@return table[]
function M.panes_menu()
  local items = {
    {
      label = "Split Right",
      keys = "<M-v>",
      run = function()
        M.split "right"
      end,
    },
    {
      label = "Split Down",
      keys = "<M-h>",
      run = function()
        M.split "below"
      end,
    },
    {
      label = "Split Left",
      run = function()
        M.split "left"
      end,
    },
    {
      label = "Split Up",
      run = function()
        M.split "above"
      end,
    },
    { sep = true },
    {
      label = "Layout: Two Columns",
      keys = "<leader>V2",
      run = function()
        M.layout "double"
      end,
    },
    {
      label = "Layout: Three Columns",
      keys = "<leader>V3",
      run = function()
        M.layout "triple"
      end,
    },
    {
      label = "Layout: Main + Two",
      keys = "<leader>Vm",
      run = function()
        M.layout "main"
      end,
    },
    {
      label = "Layout: 2x2 Grid",
      keys = "<leader>V4",
      run = function()
        M.layout "quad"
      end,
    },
    { sep = true },
    { label = "Next Pane", keys = "<C-w>w", run = M.next_pane },
    { label = "Previous Pane", keys = "<C-w>W", run = M.previous_pane },
    { label = "Equal Sizes", keys = "<leader>V=", run = M.equal_panes },
    { label = "Rotate", keys = "<leader>Vr", run = M.rotate_panes },
    { label = "Swap With Next", keys = "<leader>Vs", run = M.swap_panes },
    { label = "Zoom (Toggle)", keys = "<M-z>", run = M.zoom_pane },
    { sep = true },
    { label = "Start Screen Here", keys = "<leader>Vd", run = M.dashboard },
    { label = "Terminal Pane", hint = "Ctrl+Shift+J", run = M.toggle_terminal_pane },
    { label = "List Panes…", keys = "<leader>Vl", run = M.list_panes },
    { label = "Close Pane", keys = "<M-q>", run = M.close_pane },
    { label = "Close Other Panes", keys = "<leader>VX", run = M.close_other_panes },
  }
  return items
end

return M
