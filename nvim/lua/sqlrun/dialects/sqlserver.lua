-- SQL Server: sqlcmd. `-b` stops at the first error, `-W` trims the padding, `-s "\t"` and `-h -1` give the schema
-- shape. The password goes in SQLCMDPASSWORD; a local server gets `-C` (a dev certificate) unless the URL says not to.
-- `EXPLAIN` does not exist: SHOWPLAN_ALL estimates and STATISTICS PROFILE runs it (each one in its own GO batch).
local url = require "sqlrun.url"
local dialects = require "sqlrun.dialects"

local M = {
  label = "SQL Server",
  short = "MSSQL",
  schemes = { "sqlserver", "mssql" },
  extensions = {},
  client = "sqlcmd",
  sqls = "mssql",
  sqlfluff = "tsql",
  formatter = "transactsql",
  install = "mssql-tools18 (pacman -S mssql-tools18 · apt install mssql-tools18) · go install github.com/microsoft/go-sqlcmd/cmd/sqlcmd@latest",
  tip = "a local server gets `-C` (its certificate is trusted); for a remote one add `?trustServerCertificate=true`, and `GO` separates batches.",
}

---@param c SqlConnection
---@return string[]?, table<string, string>?, string?
local function connection_args(c)
  local parsed = url.parse(c.target)
  if not parsed then
    return nil, nil, "the sqlcmd client needs a sqlserver:// URL"
  end
  local args = { "-b", "-r", "1", "-W", "-f", "65001", "-l", "30" }
  if parsed.host then
    local host = parsed.host:find(":", 1, true) and ("[" .. parsed.host .. "]") or parsed.host
    args[#args + 1] = "-S"
    args[#args + 1] = host .. (parsed.port and ("," .. parsed.port) or "")
  end
  if parsed.user then
    args[#args + 1] = "-U"
    args[#args + 1] = parsed.user
  else
    args[#args + 1] = "-E"
  end
  if parsed.database and parsed.database ~= "" then
    args[#args + 1] = "-d"
    args[#args + 1] = parsed.database
  end
  local trust = parsed.query.trustServerCertificate or parsed.query.trustservercertificate
  local localhost = parsed.host == "localhost" or parsed.host == "127.0.0.1" or parsed.host == "::1"
  if trust ~= "false" and (trust == "true" or localhost) then
    args[#args + 1] = "-C"
  end
  local env = { SQLCMDPASSWORD = parsed.password or "" }
  return args, env
end

---@param c SqlConnection
---@param binary string?
---@return { cmd: string[], env: table<string, string>? }?
function M.command(c, binary)
  local args, env, problem = connection_args(c)
  if not args then
    return nil, problem
  end
  table.insert(args, 1, binary or M.client)
  return { cmd = args, env = env }
end

---@param c SqlConnection
---@param sql string
---@param binary string?
---@return { cmd: string[], env: table<string, string>? }?
function M.query(c, sql, binary)
  local args, env, problem = connection_args(c)
  if not args then
    return nil, problem
  end
  vim.list_extend(args, { "-h", "-1", "-W", "-s", "\t", "-w", "65535", "-y", "0", "-Q", "set nocount on;\n" .. sql })
  table.insert(args, 1, binary or M.client)
  return { cmd = args, env = env }
end

function M.explain(_, text, analyze)
  local setting = analyze and "STATISTICS PROFILE" or "SHOWPLAN_ALL"
  return ("SET %s ON\nGO\n%s;\nGO\nSET %s OFF;\nGO"):format(setting, text, setting)
end

function M.tables()
  return M.schema_tables()
end

function M.describe(_, name)
  return M.schema_columns(nil, nil, name)
end

function M.schema_tables()
  return [[
set nocount on;
select t.table_schema, t.table_name, t.table_type, count(c.column_name)
from information_schema.tables t
left join information_schema.columns c
  on c.table_schema = t.table_schema and c.table_name = t.table_name
group by t.table_schema, t.table_name, t.table_type
order by t.table_schema, t.table_name]]
end

function M.schema_columns(_, schema, table)
  local where = "table_name = " .. dialects.literal(table)
  if schema and schema ~= "" then
    where = "table_schema = " .. dialects.literal(schema) .. " and " .. where
  end
  return [[
set nocount on;
select column_name, data_type, is_nullable, coalesce(column_default, '')
from information_schema.columns
where ]] .. where .. [[
order by ordinal_position]]
end

function M.ping()
  return "select 1 as ok;"
end

--- The URL sqls' mssql driver expects: the database is a query parameter, not the path.
---@param c SqlConnection
---@return string
function M.sqls_dsn(c)
  local parsed = url.parse(c.target)
  if not parsed then
    return c.target
  end
  local base = c.target:match "^(%a[%w+.-]*://[^/?#]*)" or c.target
  base = base:gsub("^mssql://", "sqlserver://"):gsub("^mssql%+tcp://", "sqlserver://")
  local query = vim.deepcopy(parsed.query)
  if parsed.database and parsed.database ~= "" then
    query.database = parsed.database
  end
  local qs = url.encode_query(query)
  return base .. (qs and ("?" .. qs) or "")
end

return M
