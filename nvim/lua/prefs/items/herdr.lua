-- Settings panel: the Herdr integration (see prefs/init.lua for the item contract)
return {
  {
    group = "Herdr",
    label = "Herdr",
    kind = "choice",
    id = "herdr.enabled",
    -- "auto": the binary decides (on when herdr is installed)
    choices = { { value = "auto", label = "auto" }, { value = true, label = "on" }, { value = false, label = "off" } },
  },
  {
    group = "Herdr",
    label = "Register as an agent",
    kind = "choice",
    id = "herdr.register",
    -- "auto": inside Herdr, and only when it can bring the pane back (0.10.0 and later)
    choices = { { value = "auto", label = "auto" }, { value = true, label = "on" }, { value = false, label = "off" } },
  },
  {
    group = "Herdr",
    label = "Setup",
    kind = "action",
    run = function()
      require("herdr.setup").open()
    end,
  },
}
