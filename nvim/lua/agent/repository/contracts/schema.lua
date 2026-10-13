-- ── Database schema of an entity, and the dialect in use ─────────────────────
-- Looks for the entity's table in the SQL migrations (`CREATE TABLE`, plus later `ALTER TABLE`s) or in a
-- `schema.prisma`, and deduces the dialect and the data access: from the schema syntax and the project
-- manifests (go.mod, package.json, pyproject, Cargo.toml, pom.xml...). It is agnostic: the model receives the
-- REAL table and column names and the parameter style (`$1`, `?`...) of THIS database, not an assumed one.
local discovery = require "agent.discovery"
local names = require "agent.repository.contracts.names"

local M = {}

local MANIFESTS = {
  "go.mod",
  "package.json",
  "requirements.txt",
  "pyproject.toml",
  "Cargo.toml",
  "pom.xml",
  "build.gradle",
  "build.gradle.kts",
  "composer.json",
  "pubspec.yaml",
}

-- substring (lowercase) of the manifest → dialect
local DRIVERS = {
  postgres = { "pgx", "lib/pq", "postgres", "psycopg", "asyncpg", "tokio-postgres", '"pg"', "node-postgres", "npgsql" },
  mysql = { "go-sql-driver/mysql", "mysql2", "pymysql", "mysql-connector", "mysqlclient", "aiomysql", "mariadb" },
  sqlite = { "go-sqlite3", "modernc.org/sqlite", "better-sqlite3", "sqlite3", "rusqlite", "sqlite" },
  sqlserver = { "go-mssqldb", "mssql", "tedious", "pyodbc", "sqlserver" },
}

-- substring (lowercase) → data access library
local ACCESS = {
  { "sqlx", "sqlx" },
  { "gorm", "gorm" },
  { "entgo.io", "ent" },
  { "sqlc", "sqlc" },
  { "prisma", "prisma" },
  { "typeorm", "typeorm" },
  { "sequelize", "sequelize" },
  { "knex", "knex" },
  { "drizzle", "drizzle" },
  { "sqlalchemy", "sqlalchemy" },
  { "sqlmodel", "sqlmodel" },
  { "diesel", "diesel" },
  { "jooq", "jooq" },
  { "hibernate", "hibernate" },
  { "data-jpa", "spring data jpa" },
  { "entityframework", "ef core" },
  { "dapper", "dapper" },
} -- stylua: ignore

---@param root string
---@return string
local function manifests_text(root)
  local parts = {}
  for _, name in ipairs(MANIFESTS) do
    local path = root .. "/" .. name
    if vim.fn.getfsize(path) > 0 and vim.fn.getfsize(path) < 60000 then
      parts[#parts + 1] = table.concat(vim.fn.readfile(path), "\n"):lower()
    end
  end
  return table.concat(parts, "\n")
end

---@param text string  SQL schema
---@return string?
local function dialect_from_sql(text)
  local t = text:lower()
  if
    t:find "bigserial"
    or t:find "%f[%w]serial%f[%W]"
    or t:find "jsonb"
    or t:find "timestamptz"
    or t:find "gen_random_uuid"
    or t:find "%f[%w]uuid%f[%W]"
    or t:find "::"
  then
    return "postgres"
  elseif t:find "auto_increment" or t:find "engine%s*=" or t:find "unsigned" or t:find "tinyint" or t:find "`" then
    return "mysql"
  elseif t:find "autoincrement" or t:find "without rowid" then
    return "sqlite"
  elseif t:find "identity%s*%(" or t:find "nvarchar" or t:find "%[dbo%]" then
    return "sqlserver"
  end
  return nil
end

--- Parameter syntax by dialect and language
---@param dialect string?
---@param ext string
---@return string?
function M.placeholders(dialect, ext)
  if not dialect then
    return nil
  end
  if dialect == "postgres" then
    if ext == "py" then
      return "%s (psycopg) or :name (SQLAlchemy text)"
    elseif ext == "java" or ext == "kt" or ext == "cs" or ext == "php" or ext == "dart" then
      return "? (JDBC/PDO style)"
    end
    return "$1, $2, … (numbered)"
  elseif dialect == "mysql" then
    return ext == "py" and "%s" or "? (positional)"
  elseif dialect == "sqlserver" then
    return "@p1, @p2, …"
  end
  return "? (positional)"
end

--- Dialect, access library and a one-line summary. The dialect comes first from the schema (more reliable) and
--- otherwise from the drivers in the manifests.
---@param root string
---@param ext string
---@param schema_text string?
---@param import_specs string[]
---@return { dialect: string?, driver: string?, access: string[], line: string }
function M.environment(root, ext, schema_text, import_specs)
  local manifest = manifests_text(root)
  local all = manifest .. "\n" .. table.concat(import_specs, "\n"):lower()
  local dialect, driver = schema_text and dialect_from_sql(schema_text) or nil, nil
  for name, list in pairs(DRIVERS) do
    for _, needle in ipairs(list) do
      if all:find(needle, 1, true) then
        driver = driver or needle
        dialect = dialect or name
      end
    end
  end
  local access = {}
  if table.concat(import_specs, " "):find "database/sql" then
    access[#access + 1] = "database/sql"
  end
  for _, a in ipairs(ACCESS) do
    if all:find(a[1], 1, true) then
      access[#access + 1] = a[2]
    end
  end
  local parts = {}
  parts[#parts + 1] = "db: " .. (dialect or "dialect unknown")
  if driver then
    parts[#parts] = parts[#parts] .. " (" .. driver .. ")"
  end
  if #access > 0 then
    parts[#parts + 1] = "access: " .. table.concat(access, ", ")
  end
  local ph = M.placeholders(dialect, ext)
  parts[#parts + 1] = ph and ("placeholders: " .. ph) or "placeholders: use the style of the sibling implementation"
  return { dialect = dialect, driver = driver, access = access, line = table.concat(parts, " · ") }
end

--- Lines of the block that starts at `first` (until the parenthesis / brace closes)
---@param lines string[]
---@param first integer
---@param closer "sql"|"prisma"
---@return string[]
local function block(lines, first, closer)
  local out = {}
  for i = first, math.min(first + 40, #lines) do
    out[#out + 1] = lines[i]
    local l = vim.trim(lines[i])
    if
      i > first and ((closer == "sql" and (l:find "^%)" or l:find "%)%s*;")) or (closer == "prisma" and l:find "^}"))
    then
      break
    end
  end
  return out
end

---@class AgentSchema
---@field tables { path: string, line: integer, lines: string[] }[]
---@field changes string[]  later ALTER TABLE / CREATE INDEX

--- Looks for the table definition of `entity` (SQL or Prisma) and the later changes
---@param root string
---@param entity string
---@param cb fun(schema: AgentSchema?)
function M.find(root, entity, cb)
  local tables = names.tables(entity)
  local alt = table.concat(tables, "|")
  local q = '["`\\[]?'
  local create = ("(?i)create\\s+(?:\\w+\\s+)*table\\s+(?:if\\s+not\\s+exists\\s+)?%s(?:\\w+\\.)?%s(%s)%s?\\s*(\\(|$)"):format(
    q,
    q,
    alt,
    '["`\\]]'
  )
  local alter = ("(?i)(alter\\s+table\\s+(?:if\\s+exists\\s+)?(?:only\\s+)?%s(?:\\w+\\.)?%s(%s)%s?\\s+(add|drop|alter|rename|modify|change)|create\\s+(?:unique\\s+)?index\\s+.*\\son\\s+%s(?:\\w+\\.)?%s(%s)\\b)"):format(
    q,
    q,
    alt,
    '["`\\]]',
    q,
    q,
    alt
  )
  local prisma = ("model\\s+%s\\s*\\{"):format(entity)

  local result = { tables = {}, changes = {} }
  local pending = 3
  local function done()
    pending = pending - 1
    if pending == 0 then
      cb((#result.tables > 0 or #result.changes > 0) and result or nil)
    end
  end

  discovery.search(root, create, { "-g", "*.sql" }, function(hits)
    for _, h in ipairs(hits) do
      if #result.tables < 2 then
        result.tables[#result.tables + 1] =
          { path = h.path, line = h.line, lines = block(vim.fn.readfile(h.path), h.line, "sql") }
      end
    end
    done()
  end)
  discovery.search(root, prisma, { "-g", "*.prisma" }, function(hits)
    for _, h in ipairs(hits) do
      if #result.tables < 2 then
        result.tables[#result.tables + 1] =
          { path = h.path, line = h.line, lines = block(vim.fn.readfile(h.path), h.line, "prisma") }
      end
    end
    done()
  end)
  discovery.search(root, alter, { "-g", "*.sql" }, function(hits)
    table.sort(hits, function(a, b)
      return a.path == b.path and a.line < b.line or a.path < b.path
    end)
    for _, h in ipairs(hits) do
      if #result.changes < 8 then
        result.changes[#result.changes + 1] = ("%s: %s"):format(vim.fn.fnamemodify(h.path, ":t"), vim.trim(h.text))
      end
    end
    done()
  end)
end

return M
