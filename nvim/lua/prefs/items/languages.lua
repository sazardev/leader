-- Settings panel: the language packs (languages/packs.lua), on or off. Off = its LSPs, formatters and linters are not
-- started nor downloaded; the choice is saved per pack (`languages.packs.<id>`) and applies on the next start (Mason
-- then installs what a pack that came on needs). See prefs/init.lua for the item contract.
local settings = require "core.settings"
local store = require "prefs.store"

local items = {}
for _, pack in ipairs(require("languages.packs").packs) do
  items[#items + 1] = {
    group = "Languages",
    label = pack.label,
    kind = "toggle",
    restart = true,
    get = function()
      for _, name in ipairs(pack.langs) do
        if not require("languages").disabled(name) then
          return true
        end
      end
      return false
    end,
    apply = function(on)
      settings.languages.packs = settings.languages.packs or {}
      settings.languages.packs[pack.id] = on
      store.save("languages.packs." .. pack.id, on)
    end,
  }
end
return items
