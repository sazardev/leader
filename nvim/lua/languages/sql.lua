-- SQL (PostgreSQL, SQLite, MySQL/MariaDB, SQL Server, DuckDB): sqls completes the real tables and columns (its
-- connections come from the project: servers/sqls.lua), SQLFluff lints in the connection's dialect (and fixes with
-- <leader>QF), sql-formatter formats in the same dialect, and a runner (lua/sqlrun/) sends the statement under the
-- cursor, a selection or the file to psql/sqlite3/mysql/sqlcmd/duckdb and shows the result in a split. Menu <leader>Q.
---@param lint table
local function setup_sqlfluff(lint)
  local base = lint.linters.sqlfluff
  if type(base) ~= "table" or base.sqlrun then
    return
  end
  local linter = vim.deepcopy(base)
  linter.sqlrun = true
  linter.args = {
    "lint",
    "--format=json",
    "--nocolor",
    "--disable-progress-bar",
    "--dialect",
    function()
      return require("sqlrun").linter_dialect()
    end,
    "-",
  }
  local parse = linter.parser
  linter.parser = function(output, bufnr)
    local diagnostics = parse(output, bufnr)
    for _, diagnostic in ipairs(diagnostics or {}) do
      local code = diagnostic.code or ""
      -- A parse or templating error is what stops the statement from being read; the style rules are warnings.
      if code:match "^PRS" or code:match "^TMP" or code:match "^LXR" then
        diagnostic.severity = vim.diagnostic.severity.ERROR
      end
    end
    return diagnostics
  end
  lint.linters.sqlfluff = linter
end

return {
  filetypes = { "sql" },
  treesitter = { "sql" },
  lsp = { "sqls" },
  mason = { full = { "sqls", "sql-formatter", "sqlfluff" } },
  formatters = { sql = { "sql_formatter" } },
  formatter_options = {
    sql_formatter = {
      prepend_args = function()
        return { "--language", require("sqlrun").formatter_dialect() }
      end,
    },
  },
  linters = { sql = { "sqlfluff" } },
  setup_lint = setup_sqlfluff,
  menu = { name = "SQL", prefix = "Q", maps = require "languages.actions.sql", groups = { S = "setup" } },
}
