-- This file must have the same structure as nvconfig.lua
-- https://github.com/NvChad/ui/blob/v3.0/lua/nvconfig.lua
-- Here the configuration is only COMPOSED; each part lives in its own module.

local settings = require "core.settings"

---@type ChadrcConfig
local M = {}

M.base46 = {
  theme = require("appearance").initial(), -- last chosen theme (or the default)
  theme_toggle = settings.theme.toggle,
  hl_override = require("ui.highlights").overrides(),
}

M.nvdash = require("ui.dashboard").config()
M.cheatsheet = require("ui.dashboard").cheatsheet()

-- the floating terminal (Alt+i): the demo's, a block in the theme's own background over the `deep` editor,
-- 5% from each side, 14% from the top, 12% from the bottom
local flat = require("ui.flat").enabled()
M.term = {
  winopts = {
    number = false,
    relativenumber = false,
    winhl = flat and "Normal:FlatTerm,NormalFloat:FlatTerm,FloatBorder:FlatTermBorder" or nil,
  },
  float = flat and { row = 0.14, col = 0.05, width = 0.88, height = 0.7, border = require("ui.flat").border() } or nil,
}

M.ui = {
  -- the statusline is delegated to lualine.nvim (see plugins/ui/lualine.lua)
  statusline = { enabled = false },
  tabufline = { enabled = false },
}

return M
