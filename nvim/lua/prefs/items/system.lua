-- Settings panel: performance, tools and the config itself (see prefs/init.lua for the item contract)
local function run(fn)
  return function()
    fn()
  end
end

return {
  {
    group = "System",
    label = "Light mode",
    kind = "choice",
    id = "light.force",
    -- `auto` forgets the saved choice: the RAM decides (core/light.lua)
    choices = { { label = "auto" }, { value = true, label = "on" }, { value = false, label = "off" } },
    restart = true,
  },
  {
    group = "System",
    label = "Plugins",
    kind = "action",
    run = run(function()
      vim.cmd "Lazy"
    end),
  },
  {
    group = "System",
    label = "Tools",
    kind = "action",
    run = run(function()
      vim.cmd "Mason"
    end),
  },
  {
    group = "System",
    label = "Info",
    kind = "action",
    run = run(function()
      require("prefs.info").open()
    end),
  },
  {
    group = "System",
    label = "Updates",
    kind = "action",
    run = run(function()
      require("update.panel").open()
    end),
  },
  { group = "System", label = "Check for updates", kind = "toggle", id = "update.enabled" },
  {
    group = "System",
    label = "Reset my choices",
    kind = "action",
    run = run(function()
      require("prefs").reset()
    end),
  },
}
