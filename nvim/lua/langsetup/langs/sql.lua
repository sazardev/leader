-- SQL setup (<leader>QS): .sql-formatter.json in the project's dialect, compose.yaml for the database, .editorconfig,
-- CI. The dialect comes from DATABASE_URL/MYSQL_URL/MSSQL_URL (or the folder's name when there is none); the formatter
-- preset writes the language its connection needs.
local M = { name = "SQL" }

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
  -- The same registry and the same connection the runner, linter and completion use: a `postgres://…/app.db`
  -- database is PostgreSQL, not SQLite. A dialect set with <leader>QD wins here too.
  local forced = require("sqlrun.dialect").get(root)
  local chosen = require("sqlrun.connections").current(root)
  local d = (forced and require("sqlrun.dialects").get(forced))
    or (chosen and require("sqlrun.dialects").get(chosen.kind))
    or require("sqlrun.dialects").fallback()
  return {
    name = vim.fs.basename(root),
    dialect = d.id,
    formatter = d.formatter,
    sqlfluff = d.sqlfluff,
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
