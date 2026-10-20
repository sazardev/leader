-- ── Desktop app: when the setup shows ────────────────────────────────────────
-- The guided setup (gui/wizard.lua) opens by itself on the first launch of the
-- app (settings.gui.onboarding), 1.2 s after VimEnter, out of the way of the first
-- frame. Afterwards the install checks run in the background and the bar's
-- "N to finish" chip, Ctrl+Shift+W and Help › Welcome open it again: on the Review
-- step once the setup was finished, from the start otherwise.
local settings = require "core.settings"
local state = require "gui.state"

local M = {}

function M.open()
  local finished = (state.read().setup or {}).finished ~= nil
  require("gui.wizard").open { step = finished and "review" or nil }
end

function M.setup()
  if settings.gui.onboarding == false then
    return
  end
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      vim.defer_fn(function()
        if not state.read().welcomed then
          M.open()
        else
          require("gui").recheck()
        end
      end, 1200)
    end,
  })
end

return M
