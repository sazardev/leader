-- DuckDB: a file (or `:memory:`) with its own CLI. `-box`/`-header` draw a result like sqlite3's; the schema queries use
-- `-list -noheader -separator "\t"`. sqls has no DuckDB driver, so completion of the real tables is not available.
local M = {
  label = "DuckDB",
  short = "DuckDB",
  schemes = { "duckdb" },
  extensions = { ".duckdb", ".ddb" },
  client = "duckdb",
  sqls = nil,
  sqlfluff = "duckdb",
  formatter = "duckdb",
  install = "pacman -S duckdb · brew install duckdb · (or the release binary from duckdb.org)",
  tip = "the file is opened in place; sqls cannot connect to it, so completion of its tables is not available.",
}

---@param c SqlConnection
---@param binary string?
---@return { cmd: string[] }
function M.command(c, binary)
  return { cmd = { binary or M.client, "-box", "-header", c.target } }
end

---@param c SqlConnection
---@param sql string
---@param binary string?
---@return { cmd: string[] }
function M.query(c, sql, binary)
  return { cmd = { binary or M.client, "-list", "-noheader", "-separator", "\t", c.target, "-c", sql } }
end

function M.explain(_, text, analyze)
  return (analyze and "EXPLAIN ANALYZE " or "EXPLAIN ") .. text .. ";"
end

function M.tables()
  return "show tables;"
end

function M.describe(_, name)
  return "describe " .. require("sqlrun.dialects").quote(name, '"') .. ";"
end

function M.schema_tables()
  return [[
select t.table_schema, t.table_name, t.table_type, count(c.column_name)
from information_schema.tables t
left join information_schema.columns c
  on c.table_schema = t.table_schema and c.table_name = t.table_name
where t.table_schema not in ('information_schema', 'pg_catalog')
group by 1, 2, 3
order by 1, 2]]
end

function M.schema_columns(_, schema, table)
  local where = "table_name = " .. require("sqlrun.dialects").literal(table)
  if schema and schema ~= "" then
    where = "table_schema = " .. require("sqlrun.dialects").literal(schema) .. " and " .. where
  end
  return [[
select column_name, data_type, is_nullable, coalesce(column_default, '')
from information_schema.columns
where ]] .. where .. [[
order by ordinal_position]]
end

function M.ping()
  return "select 1 as ok;"
end

return M
