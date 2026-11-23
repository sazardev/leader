-- ── SQL: the :Sql command and the per-buffer hook ───────────────────────────
-- `:Sql` opens the info panel; every subcommand is the same thing as its <leader>Q key (run, file, explain, analyze,
-- tables, describe, schema, connections, dialect, favorite(s), check, plan, ping, fix, format, stop, new). The FileType
-- hook loads sqlrun for a .sql buffer: the connection/dialect chip on the statusline and the local 0-token checks.
local SUBCOMMANDS = {
  "run",
  "file",
  "explain",
  "analyze",
  "tables",
  "describe",
  "schema",
  "connections",
  "dialect",
  "info",
  "history",
  "favorite",
  "favorites",
  "check",
  "plan",
  "ping",
  "fix",
  "format",
  "stop",
  "new",
}

local M = {}

function M.setup()
  vim.api.nvim_create_user_command("Sql", function(args)
    require("sqlrun").sql_command(args.fargs)
  end, {
    nargs = "*",
    desc = "SQL: run, explain, schema, connections, info…",
    complete = function(_, line)
      local prefix = line:match "^%s*%S+%s+(%S*)" or ""
      return vim.tbl_filter(function(name)
        return name:find(prefix, 1, true) == 1
      end, SUBCOMMANDS)
    end,
  })

  local group = vim.api.nvim_create_augroup("NvSql", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "sql",
    callback = function()
      require("sqlrun").attach()
    end,
  })

  -- Local checks: one debounced pass per burst of typing, never a process (SQLFluff is the process one).
  local ns = vim.api.nvim_create_namespace "sqlcheck"
  local timers = {}
  vim.api.nvim_create_autocmd({ "TextChanged", "BufWritePost", "BufEnter" }, {
    group = group,
    pattern = "*.sql",
    callback = function(ev)
      if (require("core.settings").sql or {}).check == false then
        return
      end
      if timers[ev.buf] then
        pcall(function()
          timers[ev.buf]:stop()
        end)
      end
      timers[ev.buf] = vim.defer_fn(function()
        timers[ev.buf] = nil
        if not vim.api.nvim_buf_is_valid(ev.buf) then
          return
        end
        local lines = vim.api.nvim_buf_get_lines(ev.buf, 0, -1, false)
        local text = table.concat(lines, "\n")
        local ok, diags = pcall(require("sqlrun.check").check, text, require("sqlrun").dialect())
        if ok then
          vim.diagnostic.set(ns, ev.buf, diags)
        end
      end, 250)
    end,
  })
end

return M
