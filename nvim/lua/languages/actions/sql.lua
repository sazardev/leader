-- ── SQL actions (lua/sqlrun/) ────────────────────────────────────────────────
-- The statement under the cursor (or the selection) against the project's connection, its plan, the schema browser, the
-- query history; results in a split. Connections: DATABASE_URL in .env, the SQLite/DuckDB files of the project,
-- settings.sql.connections, or one added with <leader>Qn. The dialect (PostgreSQL, SQLite, MySQL, MariaDB, SQL Server,
-- DuckDB) comes from the connection itself.
local actions = require "utils.actions"

local function sql(fn, ...)
  local args = { ... }
  return function()
    require("sqlrun")[fn](unpack(args))
  end
end

local maps = {
  { "r", "run statement or selection", sql "run", { "n", "x" } },
  { "a", "run file", sql "run_file" },
  { "e", "explain", sql("explain", false) },
  { "E", "explain analyze", sql("explain", true) },
  { "P", "plan then run", sql "plan" },
  { "t", "tables", sql "tables" },
  { "d", "describe table under cursor", sql "describe" },
  { "s", "schema browser", sql "schema" },
  { "c", "connection", sql "pick" },
  { "D", "dialect (auto/sqlite/postgres…)", sql "dialect_menu" },
  { "n", "new connection", sql "new_connection" },
  { "i", "connection info", sql "info" },
  { "h", "query history", sql "history" },
  { "v", "saved queries", sql "favorites" },
  { "V", "save query under cursor", sql "save_favorite" },
  { "p", "ping connection", sql "ping" },
  { "x", "stop query", sql "stop" },
  { "l", "last run again", sql "again" },
  { "f", "format", actions.format },
  { "F", "fix with sqlfluff", sql "fix" },
  { "K", "local checks", sql "check" },
}
return vim.list_extend(maps, require("langsetup").maps "sql")
