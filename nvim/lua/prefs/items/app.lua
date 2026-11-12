-- Settings panel: the desktop app's window and what it opens on (see prefs/init.lua for the item contract). Listed
-- only inside the app (vim.g.leader_gui): in a terminal they mean nothing. The app reads them from the bar's state
-- (gui/init.lua `state().window`), so a change reaches it at once.
local function in_app()
  return vim.g.leader_gui == true
end

local function push()
  pcall(function()
    require("gui").update()
  end)
end

return {
  {
    group = "App",
    when = in_app,
    label = "On start",
    kind = "choice",
    id = "gui.window.on_start",
    choices = {
      { value = "ask", label = "ask for a project" },
      { value = "last", label = "last project" },
      { value = "home", label = "start screen" },
    },
  },
  {
    group = "App",
    when = in_app,
    label = "Window frame",
    kind = "choice",
    id = "gui.appbar.enabled",
    choices = { { value = true, label = "Leader's, square" }, { value = false, label = "system's, bordered" } },
    apply = push,
  },
  {
    group = "App",
    when = in_app,
    label = "Bar height",
    kind = "choice",
    id = "gui.appbar.height",
    choices = {
      { value = 1.2, label = "compact" },
      { value = 1.5, label = "normal" },
      { value = 1.8, label = "airy" },
    },
    apply = push,
  },
  {
    group = "App",
    when = in_app,
    label = "Window controls",
    kind = "choice",
    id = "gui.appbar.controls",
    choices = { { value = "right", label = "right" }, { value = "left", label = "left" } },
    apply = push,
  },
  {
    group = "App",
    when = in_app,
    label = "Editor padding",
    kind = "choice",
    id = "gui.padding.x",
    choices = {
      { value = 0, label = "edge to edge" },
      { value = 4, label = "4 px" },
      { value = 8, label = "8 px" },
      { value = 12, label = "12 px" },
    },
    apply = push,
  },
  {
    group = "App",
    when = in_app,
    label = "Activity in the bar",
    kind = "toggle",
    id = "gui.appbar.activity",
    apply = push,
  },
  {
    group = "App",
    when = in_app,
    label = "Focus mode",
    kind = "action",
    show = function()
      return require("gui.workspace").focus_active() and "on" or "off"
    end,
    run = function()
      require("gui.workspace").focus()
      push()
    end,
  },
  {
    group = "App",
    when = in_app,
    label = "Toolbar…",
    kind = "action",
    run = function()
      require("gui.toolbar").customize(push)
    end,
  },
  {
    group = "App",
    when = in_app,
    label = "Font weight",
    kind = "choice",
    id = "gui.font_weight",
    choices = {
      { value = 400, label = "regular" },
      { value = 500, label = "medium" },
      { value = 600, label = "semibold" },
    },
    restart = true,
  },
  {
    group = "App",
    when = in_app,
    label = "Remember size",
    kind = "toggle",
    id = "gui.window.remember_size",
    apply = push,
  },
  {
    group = "App",
    when = in_app,
    label = "Remember position",
    kind = "toggle",
    id = "gui.window.remember_position",
    apply = push,
  },
  {
    group = "App",
    when = in_app,
    label = "Reopen maximized",
    kind = "toggle",
    id = "gui.window.remember_maximized",
    apply = push,
  },
}
