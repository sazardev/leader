-- ── UI settings that some plugin might override ──────────────────────────────
local M = {}

function M.setup()
  -- Force cmdheight=0 after the full load (overrides any plugin that resets it)
  vim.api.nvim_create_autocmd("VimEnter", {
    group = vim.api.nvim_create_augroup("ForceCmdheight", { clear = true }),
    once = true,
    callback = function()
      vim.o.cmdheight = 0
    end,
  })

  -- the start screen (ui/start): at startup with no file, and `:Nvdash`
  require("ui.start").setup()
end

return M
