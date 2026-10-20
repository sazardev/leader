-- Formatting: per-filetype formatters declared in lua/languages/.
return {
  "stevearc/conform.nvim",
  event = "BufWritePre",
  opts = {
    formatters_by_ft = require("languages").formatters(),
    formatters = require("languages").formatter_options(), -- per-formatter options the languages declare
    -- functions, so <leader>Sf (settings panel) can turn it off and on without a restart; normal files are formatted
    -- before the write, big ones right after it, in the background (lua/core/saveformat.lua)
    format_on_save = require("core.saveformat").on_save,
    format_after_save = require("core.saveformat").after_save,
  },
  config = function(_, opts)
    require("conform").setup(opts)
  end,
}
