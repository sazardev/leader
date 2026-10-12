-- Este archivo debe tener la misma estructura que nvconfig.lua
-- https://github.com/NvChad/ui/blob/v3.0/lua/nvconfig.lua
-- Aquí solo se COMPONE la configuración; cada parte vive en su módulo.

local settings = require "core.settings"

---@type ChadrcConfig
local M = {}

M.base46 = {
  theme = require("appearance").initial(), -- último tema elegido (o el default)
  theme_toggle = settings.theme.toggle,
  hl_override = require("ui.highlights").overrides(),
}

M.nvdash = require("ui.dashboard").config()
M.cheatsheet = require("ui.dashboard").cheatsheet()

M.ui = {
  -- statusline se delega a lualine.nvim (ver plugins/ui/lualine.lua)
  statusline = { enabled = false },
  tabufline = { enabled = false },
}

return M
