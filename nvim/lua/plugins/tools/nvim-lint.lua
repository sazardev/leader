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

    --- The filetype's linters that are installed: a tool a language can use but you never installed (swiftlint on
    --- Linux, checkmake…) is skipped instead of failing on every save
    local function run()
      local names = vim.tbl_filter(function(name)
        local linter = lint.linters[name]
        if type(linter) == "function" then
          linter = linter()
        end
        local cmd = type(linter) == "table" and linter.cmd or nil
        if type(cmd) == "function" then
          cmd = cmd()
        end
        return type(cmd) == "string" and vim.fn.executable(cmd) == 1
      end, lint.linters_by_ft[vim.bo.filetype] or {})
      if #names > 0 then
        lint.try_lint(names)
      end
    end

    local group = vim.api.nvim_create_augroup("NvimLint", { clear = true })

    vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost" }, {
      group = group,
      callback = run,
    })

    -- InsertLeave: only lightweight linters (golangci-lint analyzes the whole
    -- package and running it on every insert exit saturates the CPU).
    vim.api.nvim_create_autocmd("InsertLeave", {
      group = group,
      callback = function()
        if not vim.tbl_contains(skip_insert_leave, vim.bo.filetype) then
          run()
        end
      end,
    })
  end,
}
