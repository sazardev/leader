-- Formatting: per-filetype formatters declared in lua/languages/.
local save = require("core.settings").format_on_save

return {
  "stevearc/conform.nvim",
  event = "BufWritePre",
  opts = {
    formatters_by_ft = require("languages").formatters(),
    format_on_save = save.enabled and { timeout_ms = save.timeout_ms, lsp_format = "fallback" } or nil,
  },
  config = function(_, opts)
    require("conform").setup(opts)
  end,
}
