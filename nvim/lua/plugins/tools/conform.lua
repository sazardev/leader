-- Formatting: per-filetype formatters declared in lua/languages/.
local save = require("core.settings").format_on_save

return {
  "stevearc/conform.nvim",
  event = "BufWritePre",
  opts = {
    formatters_by_ft = require("languages").formatters(),
    -- a function, so <leader>Sf (settings panel) can turn it off and on without a restart
    format_on_save = function()
      if save.enabled then
        return { timeout_ms = save.timeout_ms, lsp_format = "fallback" }
      end
    end,
  },
  config = function(_, opts)
    require("conform").setup(opts)
  end,
}
