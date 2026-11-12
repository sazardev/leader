-- ── Desktop app: the toolbar's tools ─────────────────────────────────────────
-- Every button the app bar can show, on which side, on by default or not, with
-- its icon, the tooltip it shows (with its key) and the action it runs (gui/init.lua
-- `M.actions`). What is on is yours: a right click on the bar (or View › Customize
-- Toolbar) opens a checklist, saved in gui/state.lua, that wins over the defaults.
-- The information chips on the right (recording, git changes, …) are in the same
-- panel. Icons are Nerd Font glyphs; the app draws them.
local state = require "gui.state"
local workspace = require "gui.workspace"

local M = {}

local function shortcut(action, fallback)
  local spec = (require("core.settings").gui.shortcuts or {})[action]
  if type(spec) == "string" and spec ~= "" then
    local ok, menu = pcall(require, "gui.menu")
    if ok and menu.describe then
      return menu.describe(spec)
    end
  end
  return fallback
end

local function project_name()
  local cwd = vim.uv.cwd() or ""
  return cwd:match "([^/\\]+)[/\\]*$" or cwd
end

local agent_cache, agent_at

local function agent_label()
  local now = vim.uv.now()
  if agent_cache and now - agent_at < 1000 then
    return agent_cache
  end
  local ok, selection = pcall(require, "agent.selection")
  local sel = ok and selection.current() or nil
  agent_cache = sel and selection.label(sel) or "none yet"
  agent_at = now
  return agent_cache
end

local function theme_name()
  local ok, appearance = pcall(require, "appearance")
  return ok and appearance.current() or "?"
end

---@class GuiTool
---@field id string
---@field side "left"|"right"
---@field on boolean        shown unless you turn it off
---@field title string      its name in the customize panel
---@field desc string
---@field icon string
---@field label (fun(): string)?  a label after the icon (then a ▾: it opens a menu)
---@field tip fun(): string
---@field action string
---@field active (fun(): boolean)?

---@type GuiTool[]
M.TOOLS = {
  {
    id = "project",
    side = "left",
    on = true,
    title = "Project",
    desc = "the folder you are in; opens your projects",
    icon = "",
    label = project_name,
    tip = function()
      return "Projects · Ctrl+Shift+O"
    end,
    action = "projects",
  },
  {
    id = "home",
    side = "left",
    on = true,
    title = "Home",
    desc = "the start screen",
    icon = "\u{f015}",
    tip = function()
      return "Home · Ctrl+Shift+H"
    end,
    action = "home",
  },
  {
    id = "history",
    side = "left",
    on = true,
    title = "Recent files",
    desc = "the files you opened lately",
    icon = "\u{f1da}",
    tip = function()
      return "Recent files · Ctrl+Shift+R"
    end,
    action = "history",
  },
  {
    id = "quick_open",
    side = "left",
    on = true,
    title = "Quick open",
    desc = "find a file by name",
    icon = "\u{f002}",
    tip = function()
      return "Quick open · " .. shortcut("quick_open", "Space f f")
    end,
    action = "quick_open",
  },
  {
    id = "search",
    side = "left",
    on = false,
    title = "Command palette",
    desc = "every menu item and key in one search",
    icon = "\u{f002}",
    tip = function()
      return "Command palette · Ctrl+Shift+P"
    end,
    action = "palette",
  },
  {
    id = "tree",
    side = "left",
    on = true,
    title = "File tree",
    desc = "shows or hides the tree; lit while it is open",
    icon = "\u{f07b}",
    tip = function()
      return "File tree · " .. shortcut("tree", "Ctrl+N")
    end,
    action = "tree",
    active = workspace.tree_open,
  },
  {
    id = "terminal",
    side = "right",
    on = false,
    title = "Terminal",
    desc = "the floating terminal (the pane is next to it)",
    icon = "\u{f120}",
    tip = function()
      return "Terminal · " .. shortcut("terminal", "Alt+I")
    end,
    action = "terminal",
    active = workspace.terminal_open,
  },
  {
    id = "problems",
    side = "right",
    on = false,
    title = "Problems",
    desc = "the diagnostics of the project",
    icon = "\u{f188}",
    tip = function()
      return "Problems · Space x x"
    end,
    action = "problems",
    active = workspace.problems_open,
  },
  {
    id = "panes",
    side = "right",
    on = true,
    title = "Panes",
    desc = "split, lay out and move between panes",
    icon = "\u{f009}",
    tip = function()
      return "Panes · " .. shortcut("panes", "Space V")
    end,
    action = "panes",
    active = workspace.panes_active,
  },
  {
    id = "focus",
    side = "right",
    on = false,
    title = "Focus mode",
    desc = "hide the app bar and the statusline; the code gets the whole window",
    icon = "\u{f06e}",
    tip = function()
      return "Focus mode · " .. shortcut("focus", "Ctrl+Alt+Z")
    end,
    action = "focus",
    active = workspace.focus_active,
  },
  {
    id = "agent",
    side = "right",
    on = true,
    title = "Agent",
    desc = "which AI agent and model the editor uses; pick another",
    icon = "\u{f0e7}",
    tip = function()
      return "Agent · " .. agent_label()
    end,
    action = "agent",
  },
  {
    id = "chat",
    side = "right",
    on = true,
    title = "Chat",
    desc = "the persistent Leader Chat (backend-agnostic, <leader>aC)",
    icon = "\u{f086}",
    tip = function()
      return "Chat · " .. shortcut("chat", "Space a C")
    end,
    action = "chat",
    active = workspace.chat_open,
  },
  {
    id = "theme",
    side = "right",
    on = true,
    title = "Theme",
    desc = "pick a theme, light or dark (previewed as you move)",
    icon = "\u{f1fc}",
    tip = function()
      return "Theme · " .. theme_name()
    end,
    action = "theme",
  },
  {
    id = "settings",
    side = "right",
    on = false,
    title = "Settings",
    desc = "the settings panel",
    icon = "\u{f013}",
    tip = function()
      return "Settings · Space S p"
    end,
    action = "settings",
  },
  {
    id = "setup",
    side = "right",
    on = false,
    title = "Set up",
    desc = "the guided setup: languages, features, agent, installs",
    icon = "\u{f0ad}",
    tip = function()
      return "Set up Leader · Ctrl+Shift+W"
    end,
    action = "welcome",
  },
}

--- The information chips on the right (gui/init.lua draws them), by the `show` key they use.
M.CHIPS = {
  {
    id = "update",
    title = "A newer Leader is available",
    desc = "↑ 1.9.0: click for what changed and to update",
    on = true,
  },
  { id = "setup", title = "What is left to install", desc = "opens the setup when something is missing", on = true },
  { id = "recording", title = "Macro being recorded", desc = "REC @q while you record", on = true },
  { id = "git", title = "Git changes of the file", desc = "+3 ~1 -2", on = true },
  { id = "format", title = "Unusual encoding or line endings", desc = "latin1, dos", on = true },
  { id = "lsp", title = "Language servers", desc = "the LSPs attached to the file", on = false },
  { id = "indent", title = "Indent", desc = "␣2 for spaces, ⇥4 for tabs", on = false },
}

---@return table<string, boolean> what you changed (id → on/off)
local function chosen()
  return (state.read().toolbar or {})
end

---@param id string
---@param default boolean
---@return boolean
function M.enabled(id, default)
  local v = chosen()[id]
  if v == nil then
    return default
  end
  return v
end

--- The tools to draw, as the app wants them.
---@param defaults table<string, boolean>? settings.gui.appbar.buttons: on/off before you choose in the panel
---@return table[] left, table[] right
function M.tools(defaults)
  defaults = defaults or {}
  local left, right = {}, {}
  for _, t in ipairs(M.TOOLS) do
    local default = defaults[t.id]
    if default == nil then
      default = t.on
    end
    if M.enabled(t.id, default) then
      local ok_tip, tip = pcall(t.tip)
      local item = {
        icon = t.icon,
        label = t.label and t.label() or nil,
        tip = ok_tip and tip or t.title,
        action = t.action,
        menu = t.label ~= nil,
        active = t.active and t.active() or false,
      }
      table.insert(t.side == "left" and left or right, item)
    end
  end
  return left, right
end

--- The chips to show: the settings' `show`, with your choices on top.
---@param show table settings.gui.appbar.show
---@return table<string, boolean>
function M.chips(show)
  local out = {}
  for _, c in ipairs(M.CHIPS) do
    local default = show[c.id]
    if default == nil then
      default = c.on
    end
    out[c.id] = M.enabled("chip." .. c.id, default)
  end
  return out
end

--- The customize panel: every tool and chip, checked when it is on.
---@param on_done fun()?
function M.customize(on_done)
  local settings = require "core.settings"
  local show = (settings.gui.appbar or {}).show or {}
  local items, ids = {}, {}
  local defaults = (settings.gui.appbar or {}).buttons or {}
  for _, t in ipairs(M.TOOLS) do
    local default = defaults[t.id]
    if default == nil then
      default = t.on
    end
    items[#items + 1] = {
      label = t.title,
      desc = t.desc,
      checked = M.enabled(t.id, default),
      group = t.side == "left" and "Left of the path" or "Right of the path",
    }
    ids[#ids + 1] = t.id
  end
  local chips = M.chips(show)
  for _, c in ipairs(M.CHIPS) do
    items[#items + 1] = { label = c.title, desc = c.desc, checked = chips[c.id], group = "Information" }
    ids[#ids + 1] = "chip." .. c.id
  end
  require("utils.modal").checklist(items, {
    title = "Customize toolbar",
    intro = { { { "  What the bar shows. Space checks, Enter saves; a click works too.", "NvModalMuted" } }, "" },
    confirm = "Save",
    clean = true,
  }, function(picked)
    local on = {}
    for _, i in ipairs(picked) do
      on[i] = true
    end
    local choice = {}
    for i, id in ipairs(ids) do
      choice[id] = on[i] == true
    end
    state.update { toolbar = choice }
    if on_done then
      on_done()
    end
  end)
end

return M
