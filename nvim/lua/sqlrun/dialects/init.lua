-- ── SQL dialects ─────────────────────────────────────────────────────────────
-- One file per engine under `dialects/`: how a connection becomes a client command, which dialect each tool speaks
-- (sqls, SQLFluff, sql-formatter) and how its schema is read. This module is the registry: detection from a URL or a
-- file, the client binary that is installed, and the fallback for a project with no connection. Pure, so the runner,
-- the LSP config, the formatter and the linter all answer the same thing (tested in test-langs.lua).
local M = {}

-- stylua: ignore start
local NAMES = { "postgres", "sqlite", "mysql", "mariadb", "sqlserver", "duckdb" }
-- stylua: ignore end

local ALIASES = {
  postgresql = "postgres",
  pgsql = "postgres",
  psql = "postgres",
  pg = "postgres",
  sqlite3 = "sqlite",
  mariadb = "mariadb",
  mysql = "mysql",
  mssql = "sqlserver",
  sqlserver = "sqlserver",
  tsql = "sqlserver",
  transactsql = "sqlserver",
  duckdb = "duckdb",
}

---@type table<string, SqlDialect>
local cache = {}

--- The canonical id of a dialect name (`postgresql` → `postgres`, `mssql` → `sqlserver`)
---@param name string?
---@return string?
function M.alias(name)
  if type(name) ~= "string" or name == "" then
    return nil
  end
  local lower = name:lower()
  return ALIASES[lower] or lower
end

---@class SqlDialect
---@field id string
---@field label string
---@field short string             a chip-sized name ("PG", "MySQL")
---@field schemes string[]         URL schemes (`postgres`, `mysql`…)
---@field extensions string[]      file extensions for a file database (`.db`, `.duckdb`)
---@field client string            the executable that runs a statement
---@field alts string[]?           other executables, in order (mariadb → mysql)
---@field sqls string?             sqls driver, nil when it cannot speak this dialect
---@field sqlfluff string          SQLFluff's dialect name
---@field formatter string         sql-formatter's language name
---@field install string           how to get the client
---@field tip string               one line of advice for the info panel
---@field command fun(c: SqlConnection, binary: string?): { cmd: string[], env: table<string, string>? }
---@field query fun(c: SqlConnection, sql: string, binary: string?): { cmd: string[], env: table<string, string>? }
---@field explain fun(c: SqlConnection, text: string, analyze: boolean?): string
---@field tables fun(c: SqlConnection): string
---@field describe fun(c: SqlConnection, name: string): string
---@field schema_tables fun(c: SqlConnection): string
---@field schema_columns fun(c: SqlConnection, schema: string?, table: string): string
---@field ping fun(c: SqlConnection): string
---@field sqls_dsn fun(c: SqlConnection): string?

---@param id string
---@return SqlDialect?
function M.get(id)
  local name = M.alias(id)
  if not name or not vim.tbl_contains(NAMES, name) then
    return nil
  end
  if not cache[name] then
    cache[name] = require("sqlrun.dialects." .. name)
    cache[name].id = name
  end
  return cache[name]
end

--- Every dialect, in menu order
---@return SqlDialect[]
function M.all()
  local out = {}
  for _, name in ipairs(NAMES) do
    out[#out + 1] = M.get(name)
  end
  return out
end

--- The target without the scheme of a file database (`sqlite:///data/app.db` → `/data/app.db`)
---@param id string
---@param target string
---@return string
function M.normalize(id, target)
  if id ~= "sqlite" and id ~= "duckdb" then
    return (target:gsub("^(%a[%w+.-]*)://", function(scheme)
      return scheme:lower() .. "://"
    end))
  end
  local value = target:gsub("^%a[%w+.-]*://", ""):gsub("^[Ff][Ii][Ll][Ee]:", "")
  if value:sub(1, 2) == "//" then
    value = value:sub(3)
  elseif value:sub(1, 1) ~= "/" and target:match "^file:///" then
    value = "/" .. value
  end
  if value:match "^/[%a]:[/\\]" then -- file:///C:/x on Windows is C:/x for the client
    value = value:sub(2)
  end
  return value
end

--- What a target is: a dialect id and the target as the client takes it
---@param target string?
---@return string? id, string? value
function M.detect(target)
  if type(target) ~= "string" or vim.trim(target) == "" then
    return nil
  end
  local lower = target:lower()
  local scheme = lower:match "^(%a[%w+.-]*)://"
  if scheme then
    -- SQLAlchemy writes `postgresql+asyncpg://`, `mysql+pymysql://`, `sqlite+aiosqlite:///`: the client wants the
    -- plain scheme, but the dialect is the same one.
    local base = scheme:gsub("%+.*$", "")
    local value = base ~= scheme and target:gsub("^%a[%w+.-]*://", base .. "://") or target
    for _, name in ipairs(NAMES) do
      local d = M.get(name)
      if vim.tbl_contains(d.schemes, base) then
        local target_value = M.normalize(name, value)
        if name == "sqlite" and (target_value:lower():match "%.duckdb$" or target_value:lower():match "%.ddb$") then
          return "duckdb", target_value
        end
        return name, target_value
      end
    end
  end
  if lower:match "^file:" then
    local value = M.normalize("sqlite", target)
    if value:lower():match "%.duckdb$" or value:lower():match "%.ddb$" then
      return "duckdb", value
    end
    return "sqlite", value
  end
  if lower:match "^server=" then
    return "sqlserver", target
  end
  if lower:match "@tcp%(" then
    return "mysql", target
  end
  if lower:match "^host=" and lower:match "dbname=" then
    return "postgres", target
  end
  for _, name in ipairs(NAMES) do
    local d = M.get(name)
    for _, ext in ipairs(d.extensions or {}) do
      if lower:sub(-#ext) == ext then
        return name, target
      end
    end
  end
  return nil
end

--- The binary that is installed for a dialect: its client, else the first alternative, else the client (the caller
--- reports that it is missing)
---@param id string
---@return string
function M.binary(id)
  local d = M.get(id)
  if not d then
    return "psql"
  end
  local names = { d.client }
  vim.list_extend(names, d.alts or {})
  for _, name in ipairs(names) do
    if vim.fn.executable(name) == 1 then
      return name
    end
  end
  return d.client
end

--- The dialect a project uses when no connection was found (`settings.sql.dialect`)
---@return SqlDialect
function M.fallback()
  local settings = require("core.settings").sql or {}
  return M.get(settings.dialect) or M.get "postgres"
end

--- A single-quoted SQL literal (works in every dialect we speak)
---@param value string
---@return string
function M.literal(value)
  return "'" .. tostring(value):gsub("'", "''") .. "'"
end

--- An identifier quoted the way a dialect wants it
---@param id string
---@param quote string
---@return string
function M.quote(id, quote)
  local parts = vim.split(id, ".", { plain = true })
  for i, part in ipairs(parts) do
    parts[i] = quote .. part:gsub(quote, quote .. quote) .. quote
  end
  return table.concat(parts, ".")
end

return M
