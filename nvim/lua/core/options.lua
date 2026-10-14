-- ── Neovim options ───────────────────────────────────────────────────────────
-- The values live in core/settings.lua (`options`); here they are only applied.
local settings = require "core.settings"

local M = {}

function M.setup()
  require "nvchad.options"

  for name, value in pairs(settings.options) do
    vim.o[name] = value
  end

  vim.diagnostic.config(settings.diagnostics)

  vim.opt.shortmess:append "c" -- silences completion messages

  -- Clean floats (no loud borders). With the flat design (ui/flat) floats are filled blocks instead: no remapping needed
  if not require("ui.flat").enabled() then
    vim.o.winhighlight = "NormalFloat:Normal,FloatBorder:Comment,FloatTitle:Comment"
  end
end

return M
