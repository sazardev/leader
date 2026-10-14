-- Settings panel: how the editor looks (see prefs/init.lua for the item contract)
local function appearance()
  return require "appearance"
end

local function flat_on()
  return require("ui.flat").enabled()
end

return {
  {
    group = "Appearance",
    label = "Theme",
    kind = "action",
    show = function()
      return appearance().current()
    end,
    run = function()
      local select = require "agent.ui.select"
      local function done(what)
        return function()
          if what() then
            require("utils.log").info("Theme: " .. appearance().current())
          end
        end
      end
      local items = {
        { label = "Toggle light / dark", run = appearance().toggle },
        {
          label = ("Default (%s)"):format(appearance().default()),
          run = done(function()
            return appearance().use(appearance().default())
          end),
        },
        {
          label = "Terminal theme (Alacritty)",
          run = done(function()
            return appearance().use(appearance().TERMINAL)
          end),
        },
        {
          label = "Re-sync the terminal theme",
          run = done(function()
            return appearance().use(appearance().TERMINAL)
          end),
        },
        {
          label = "Pick from the catalog…",
          run = function()
            require("nvchad.themes").open()
          end,
        },
      }
      select.pick(items, { title = "Theme", on_cancel = require("prefs").open }, function(choice)
        choice.run()
      end)
    end,
  },
  { group = "Appearance", label = "Motion", kind = "toggle", id = "ui.motion" },
  {
    group = "Appearance",
    label = "Blinking cursor",
    kind = "toggle",
    id = "ui.blink_cursor",
    apply = function(on)
      if flat_on() then
        vim.o.guicursor = "n-v-c-sm:block,i-ci-ve:ver25,r-cr-o:hor20"
          .. (on and ",a:blinkwait700-blinkoff400-blinkon250" or "")
      end
    end,
  },
  {
    group = "Appearance",
    label = "Flash on change",
    kind = "choice",
    id = "ui.fresh_ms",
    choices = { { value = 450, label = "on" }, { value = 0, label = "off" } },
  },
  {
    group = "Appearance",
    label = "Show keys",
    kind = "toggle",
    id = "ui.keys",
    get = function()
      return require("ui.flat.keys").is_on()
    end,
    apply = function(on)
      require("ui.flat.keys").set(on)
    end,
  },
  { group = "Appearance", label = "Flat design", kind = "toggle", id = "ui.flat", restart = true },
}
