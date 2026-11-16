-- PostgreSQL: psql takes the URL as it is (it also reads ~/.pgpass and the PG* variables). `-w` makes a missing
-- password fail instead of prompting, which would hang the editor; `-t -A -F "\t"` is the schema shape (one row a line).
local M = {
  label = "PostgreSQL",
  short = "PG",
  schemes = { "postgres", "postgresql" },
  extensions = {},
  client = "psql",
  sqls = "postgresql",
  sqlfluff = "postgres",
  formatter = "postgresql",
  install = "pacman -S postgresql · apt install postgresql-client · brew install libpq",
  tip = "psql reads ~/.pgpass and PG*: a URL with no password works when one of those has it.",
}

---@param c SqlConnection
---@param binary string?
---@return { cmd: string[], env: table<string, string>? }
function M.command(c, binary)
  return {
    cmd = {
      binary or M.client,
      c.target,
      "-X",
      "-w",
      "-v",
      "ON_ERROR_STOP=1",
      "-P",
      "pager=off",
      "-P",
      "null=∅",
    },
  }
end

---@param c SqlConnection
---@param sql string
---@param binary string?
---@return { cmd: string[], env: table<string, string>? }
function M.query(c, sql, binary)
  return {
    cmd = {
      binary or M.client,
      c.target,
      "-X",
      "-w",
      "-v",
      "ON_ERROR_STOP=1",
      "-P",
      "pager=off",
      "-t",
      "-A",
      "-F",
      "\t",
      "-c",
      sql,
    },
  }
end

function M.explain(_, text, analyze)
  return (analyze and "EXPLAIN (ANALYZE, BUFFERS) " or "EXPLAIN ") .. text .. ";"
end

function M.tables()
  return "\\dt+"
end

function M.describe(_, name)
  return "\\d+ " .. name
end

function M.schema_tables()
  return [[
select t.table_schema, t.table_name, t.table_type, count(c.column_name)
from information_schema.tables t
left join information_schema.columns c
  on c.table_schema = t.table_schema and c.table_name = t.table_name
where t.table_schema not in ('pg_catalog', 'information_schema')
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

---@param c SqlConnection
---@return string
function M.sqls_dsn(c)
  return c.target
end

return M
