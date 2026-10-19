-- SQL (PostgreSQL, SQLite): sqls for completion of the real tables and columns (its connections come from the project:
-- servers/sqls.lua), sql-formatter in the project's dialect, and a runner (lua/sqlrun/) that sends the statement under
-- the cursor, a selection or the file to psql/sqlite3 and shows the result in a split. Menu <leader>Q.
return {
  filetypes = { "sql" },
  treesitter = { "sql" },
  lsp = { "sqls" },
  mason = { full = { "sqls", "sql-formatter" } },
  formatters = { sql = { "sql_formatter" } },
  formatter_options = {
    sql_formatter = {
      prepend_args = function()
        return { "--language", require("sqlrun").dialect() == "sqlite" and "sqlite" or "postgresql" }
      end,
    },
  },
  menu = { name = "SQL", prefix = "Q", maps = require "languages.actions.sql" },
}
