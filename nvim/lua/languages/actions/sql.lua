-- ── SQL actions (lua/sqlrun/) ────────────────────────────────────────────────
-- The statement under the cursor (or the selection) against the project's connection, its plan, the schema; results
-- in a split. Connections: DATABASE_URL in .env, the SQLite files of the project, or settings.sql.connections.
local actions = require "utils.actions"

local function sql(fn, ...)
  local args = { ... }
  return function()
    require("sqlrun")[fn](unpack(args))
  end
end

return {
  { "r", "run statement or selection", sql "run", { "n", "x" } },
  { "a", "run file", sql "run_file" },
  { "e", "explain", sql("explain", false) },
  { "E", "explain analyze", sql("explain", true) },
  { "t", "tables", sql "tables" },
  { "d", "describe table under cursor", sql "describe" },
  { "c", "connection", sql "pick" },
  { "l", "last run again", sql "again" },
  { "f", "format", actions.format },
}
