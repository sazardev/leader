-- SQL setup (<leader>QS): .sql-formatter.json in the project's dialect, compose.yaml for the database, .editorconfig,
-- CI. The dialect comes from DATABASE_URL/MYSQL_URL/MSSQL_URL (or the folder's name when there is none); the formatter
-- preset writes the language its connection needs.
local read = function(path)
  return require("utils.project").read(path)
end

local M = { name = "SQL" }

--- The engine a URL names
---@param url string
---@return string
local function dialect_of(url)
  local lower = (url or ""):lower()
  if lower:match "^sqlite" or lower:match "%.db" or lower:match "%.sqlite" then
    return "sqlite"
  end
  if lower:match "^duckdb" or lower:match "%.duckdb" then
    return "duckdb"
  end
  if lower:match "^mysql" then
    return "mysql"
  end
  if lower:match "^mariadb" then
    return "mariadb"
  end
  if lower:match "^sqlserver" or lower:match "^mssql" then
    return "sqlserver"
  end
  return "postgresql"
end

--- What sql-formatter calls it
---@param dialect string
---@return string
local function formatter(dialect)
  return dialect == "sqlserver" and "transactsql" or dialect
end

---@param dir string
---@return string
function M.root(dir)
  return vim.fs.root(dir, function(name)
    return name == ".sql-formatter.json"
      or name == ".sqlfluff"
      or name == ".env"
      or name == "compose.yaml"
      or name == "compose.yml"
      or name == "docker-compose.yml"
  end) or vim.fs.root(dir, ".git") or dir
end

---@param root string
---@return table<string, string>
function M.vars(root)
  local env = (read(root .. "/.env") or "") .. "\n" .. (read(root .. "/.env.example") or "")
  local url = env:match 'DATABASE_URL%s*=%s*"?([^"%s]+)"?'
    or env:match 'MYSQL_URL%s*=%s*"?([^"%s]+)"?'
    or env:match 'MSSQL_URL%s*=%s*"?([^"%s]+)"?'
    or env:match 'SQLITE_URL%s*=%s*"?([^"%s]+)"?'
    or ""
  local dialect = dialect_of(url)
  return {
    name = vim.fs.basename(root),
    dialect = dialect,
    formatter = formatter(dialect),
    sqlfluff = dialect == "postgresql" and "postgres" or (dialect == "sqlserver" and "tsql" or dialect),
  }
end

M.topics = {
  { id = "formatter", key = "f", label = ".sql-formatter.json", default = "postgresql", core = true },
  {
    id = "compose",
    key = "c",
    label = "compose.yaml (database)",
    default = "postgres",
    alts = { "docker-compose.yml", "docker-compose.yaml", "compose.yml" },
  },
  { id = "editorconfig", key = "e", label = ".editorconfig", default = "sql", core = true },
  { id = "ci", key = "y", label = "GitHub Actions CI", default = "github", alts = { ".github/workflows/ci.yaml" } },
}

return M
