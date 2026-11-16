-- SQLite: the file is opened in place with sqlite3. `-bail` stops at the first error, `-box` draws the result as a
-- table, and the schema queries use the tab-separated shape. `.timeout` avoids failing at once on a locked database.
local M = {
  label = "SQLite",
  short = "SQLite",
  schemes = { "sqlite", "sqlite3", "file" },
  extensions = { ".db", ".sqlite", ".sqlite3" },
  client = "sqlite3",
  sqls = "sqlite3",
  sqlfluff = "sqlite",
  formatter = "sqlite",
  install = "pacman -S sqlite · apt install sqlite3 · brew install sqlite",
  tip = "the file is edited in place: a second client (or a migration) can lock it for a moment.",
}

---@param c SqlConnection
---@param binary string?
---@return { cmd: string[] }
function M.command(c, binary)
  return {
    cmd = { binary or M.client, "-bail", "-header", "-box", "-cmd", ".timeout 5000", c.target },
  }
end

---@param c SqlConnection
---@param sql string
---@param binary string?
---@return { cmd: string[] }
function M.query(c, sql, binary)
  return {
    cmd = { binary or M.client, "-bail", "-noheader", "-separator", "\t", "-cmd", ".timeout 5000", c.target, sql },
  }
end

function M.explain(_, text)
  return "EXPLAIN QUERY PLAN " .. text .. ";"
end

function M.tables()
  return ".tables"
end

function M.describe(_, name)
  return ".schema " .. name
end

function M.schema_tables()
  return [[
select 'main', m.name, case m.type when 'view' then 'VIEW' else 'BASE TABLE' end,
       (select count(*) from pragma_table_info(m.name))
from sqlite_master m
where m.type in ('table', 'view') and m.name not like 'sqlite_%'
order by 2]]
end

function M.schema_columns(_, _, table)
  return [[
select name, type, case "notnull" when 1 then 'NO' else 'YES' end, coalesce(dflt_value, ''), pk
from pragma_table_info(]] .. require("sqlrun.dialects").literal(table) .. [[
)
order by cid]]
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
