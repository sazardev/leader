-- ── Appearance: persistence and sync with the terminal ───────────────────────
local M = {}

function M.setup()
  local group = vim.api.nvim_create_augroup("Appearance", { clear = true })

  -- Any theme change (also from the NvChad picker) is remembered
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "NvThemeReload",
    callback = function()
      require("appearance").persist()
    end,
  })

  -- Live tracking of Alacritty (only if the active theme is the terminal one)
  vim.schedule(function()
    require("appearance").watch()
  end)
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      require("appearance.watcher").stop()
    end,
  })

  -- On returning to Neovim: if you changed the Alacritty theme, it follows it
  vim.api.nvim_create_autocmd("FocusGained", {
    group = group,
    callback = function()
      vim.schedule(function()
        local appearance = require "appearance"
        if appearance.current() == appearance.TERMINAL and appearance.sync() then
          require("utils.log").info "Terminal theme updated"
        end
      end)
    end,
  })
end

return M
