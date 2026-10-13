-- "terminal" theme: base46 loads it as `themes.terminal` (lua/themes/ is its
-- user themes folder). The logic lives in lua/appearance/.
local loaded = require("appearance.alacritty").load()
if not loaded then
  error "terminal theme: Alacritty config not found"
end

local theme =
  require("appearance.terminal_theme").build(loaded.palette, require("core.settings").theme.terminal.min_contrast)

return require("base46").override_theme(theme, "terminal")
