-- ── SQL: the :Sql command and the per-buffer hook ───────────────────────────
-- `:Sql` opens the info panel; every subcommand is the same thing as its <leader>Q key (run, file, explain, analyze,
-- tables, describe, schema, connections, info, history, ping, fix, format, stop, new). The FileType hook loads sqlrun
-- for a .sql buffer, which is what puts the connection/dialect chip on the statusline.
local SUBCOMMANDS = {
  "run",
  "file",
  "explain",
  "analyze",
  "tables",
  "describe",
  "schema",
  "connections",
  "info",
  "history",
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
end

return M
