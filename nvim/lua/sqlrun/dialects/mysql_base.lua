-- Shared base for MySQL and MariaDB: both clients take the same flags, but MariaDB has no `--ssl-mode` and spells
-- `EXPLAIN ANALYZE` differently. The password goes in `MYSQL_PWD` (argv is visible to every process); the URL is split
-- with sqlrun/url.lua so `mysql://app:s3cret@db:3306/app` becomes the flags the client expects.
local url = require "sqlrun.url"
local dialects = require "sqlrun.dialects"

local M = {}

---@param spec table
---@return SqlDialect
function M.new(spec)
  local D = vim.tbl_extend("keep", spec, {
    alts = {},
    extensions = {},
    sqls = "mysql",
  })

  ---@param c SqlConnection
  ---@return SqlUrl? parsed, string? problem
  local function parse(c)
    local parsed = url.parse(c.target)
    if not parsed then
      return nil, "the " .. D.label .. " client needs a " .. D.schemes[1] .. ":// URL"
    end
    return parsed
  end

  --- The connection flags both commands share. MariaDB's client has no `--ssl-mode` and MySQL's has no `--skip-ssl`:
  --- the flags follow the binary that is actually installed, not the URL (a machine may only have one of them).
  ---@param c SqlConnection
  ---@param binary string?
  ---@return string[]?, table<string, string>?, string?
  local function connection_args(c, binary)
    local parsed, problem = parse(c)
    if not parsed then
      return nil, nil, problem
    end
    local maria_client = (binary or D.client) == "mariadb"
    local args = { "--default-character-set=utf8mb4" }
    if parsed.host then
      args[#args + 1] = "--host=" .. parsed.host
    end
    if parsed.port then
      args[#args + 1] = "--port=" .. parsed.port
    end
    if parsed.user then
      args[#args + 1] = "--user=" .. parsed.user
    end
    if parsed.database and parsed.database ~= "" then
      args[#args + 1] = "--database=" .. parsed.database
    end
    if parsed.query.socket then
      args[#args + 1] = "--socket=" .. parsed.query.socket
    end
    if parsed.query.protocol then
      args[#args + 1] = "--protocol=" .. parsed.query.protocol
    end
    local ssl = parsed.query["ssl-mode"] or parsed.query.sslmode
    if ssl then
      ssl = ssl:upper()
      if not maria_client then
        args[#args + 1] = "--ssl-mode=" .. ssl
      elseif ssl == "DISABLED" then
        args[#args + 1] = "--skip-ssl"
      else
        args[#args + 1] = "--ssl"
      end
    end
    local env = parsed.password and { MYSQL_PWD = parsed.password } or nil
    return args, env
  end

  ---@param c SqlConnection
  ---@param binary string?
  ---@return { cmd: string[], env: table<string, string>? }?
  function D.command(c, binary)
    local args, env, problem = connection_args(c, binary)
    if not args then
      return nil, problem
    end
    vim.list_extend(args, { "--table" })
    table.insert(args, 1, binary or D.client)
    return { cmd = args, env = env }
  end

  ---@param c SqlConnection
  ---@param sql string
  ---@param binary string?
  ---@return { cmd: string[], env: table<string, string>? }?
  function D.query(c, sql, binary)
    local args, env, problem = connection_args(c, binary)
    if not args then
      return nil, problem
    end
    vim.list_extend(args, { "--batch", "--raw", "--skip-column-names", "-e", sql })
    table.insert(args, 1, binary or D.client)
    return { cmd = args, env = env }
  end

  function D.explain(_, text, analyze)
    if analyze then
      return (D.id == "mariadb" and "ANALYZE FORMAT=JSON " or "EXPLAIN ANALYZE ") .. text .. ";"
    end
    return "EXPLAIN " .. text .. ";"
  end

  function D.tables()
    return "show full tables;"
  end

  function D.describe(_, name)
    return "describe " .. dialects.quote(name, "`") .. ";"
  end

  function D.schema_tables()
    return [[
select t.table_schema, t.table_name, t.table_type, count(c.column_name)
from information_schema.tables t
left join information_schema.columns c
  on c.table_schema = t.table_schema and c.table_name = t.table_name
where (database() is null or t.table_schema = database())
  and t.table_schema not in ('mysql', 'information_schema', 'performance_schema', 'sys')
group by 1, 2, 3
order by 1, 2]]
  end

  function D.schema_columns(_, schema, table)
    local where = "table_name = " .. dialects.literal(table)
    if schema and schema ~= "" then
      where = "table_schema = " .. dialects.literal(schema) .. " and " .. where
    else
      where = "(database() is null or table_schema = database()) and " .. where
    end
    return [[
select column_name, column_type, is_nullable, coalesce(column_default, '')
from information_schema.columns
where ]] .. where .. [[
order by ordinal_position]]
  end

  function D.ping()
    return "select 1 as ok;"
  end

  return D
end

return M
