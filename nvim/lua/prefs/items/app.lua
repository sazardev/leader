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
