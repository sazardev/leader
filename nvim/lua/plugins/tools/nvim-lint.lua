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

    -- One trailing timer per buffer: a linter is a process (Node ones cost 100-200 ms of CPU just to start), and a
    -- burst of Esc / saves / the format-after-save rewrite would otherwise start one each (nvim-lint only kills the
    -- previous run after it was spawned). The first lint of a file (BufReadPost) is immediate.
    local timers = {}
    local function lint_soon(buf)
      local timer = timers[buf]
      if not timer then
        timer = vim.uv.new_timer()
        timers[buf] = timer
      end
      timer:stop()
      timer:start(
        require("core.settings").lint.debounce_ms,
        0,
        vim.schedule_wrap(function()
          if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_get_current_buf() == buf then
            vim.api.nvim_buf_call(buf, run)
          end
        end)
      )
    end

    vim.api.nvim_create_autocmd("BufReadPost", { group = group, callback = run })
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = group,
      callback = function(ev)
        lint_soon(ev.buf)
      end,
    })
    vim.api.nvim_create_autocmd("BufDelete", {
      group = group,
      callback = function(ev)
        local timer = timers[ev.buf]
        if timer then
          timer:stop()
          timer:close()
          timers[ev.buf] = nil
        end
      end,
    })

    -- InsertLeave: only lightweight linters (golangci-lint analyzes the whole
    -- package and running it on every insert exit saturates the CPU).
    vim.api.nvim_create_autocmd("InsertLeave", {
      group = group,
      callback = function(ev)
        if not vim.tbl_contains(skip_insert_leave, vim.bo.filetype) then
          lint_soon(ev.buf)
        end
      end,
    })
  end,
}
