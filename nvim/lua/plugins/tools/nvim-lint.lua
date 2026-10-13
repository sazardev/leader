-- Linting: per-filetype linters declared in lua/languages/.
return {
  "mfussenegger/nvim-lint",
  event = { "BufReadPost", "BufWritePost", "InsertLeave" },
  config = function()
    local lint = require "lint"
    local languages = require "languages"
    local skip_insert_leave = require("core.settings").lint.skip_insert_leave

    languages.setup_lint(lint)
    lint.linters_by_ft = languages.linters()

    local group = vim.api.nvim_create_augroup("NvimLint", { clear = true })

    vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost" }, {
      group = group,
      callback = function()
        lint.try_lint()
      end,
    })

    -- InsertLeave: only lightweight linters (golangci-lint analyzes the whole
    -- package and running it on every insert exit saturates the CPU).
    vim.api.nvim_create_autocmd("InsertLeave", {
      group = group,
      callback = function()
        if not vim.tbl_contains(skip_insert_leave, vim.bo.filetype) then
          lint.try_lint()
        end
      end,
    })
  end,
}
