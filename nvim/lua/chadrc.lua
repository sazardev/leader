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

M.ui = {
  -- the statusline is delegated to lualine.nvim (see plugins/ui/lualine.lua)
  statusline = { enabled = false },
  tabufline = { enabled = false },
}

return M
