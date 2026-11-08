-- SQL setup (<leader>QS): .sql-formatter.json, compose.yaml for the database, .editorconfig, CI. Filled from
-- DATABASE_URL (dialect) or the folder's name.
local read = function(path)
  return require("utils.project").read(path)
end

local M = { name = "SQL" }

---@param dir string
---@return string
function M.root(dir)
  return vim.fs.root(dir, function(name)
    return name == ".sql-formatter.json" or name == "DATABASE_URL" or name == "compose.yaml" or name == ".env"
  end) or vim.fs.root(dir, ".git") or dir
end

---@param root string
---@return table<string, string>
function M.vars(root)
  local env = read(root .. "/.env") or ""
  local env_example = read(root .. "/.env.example") or ""
  local url = env:match "DATABASE_URL%s*=%s*(%S+)" or env_example:match "DATABASE_URL%s*=%s*(%S+)" or ""
  local dialect = url:match "^sqlite" or url:match "%.db" and "sqlite" or "postgresql"
  if dialect ~= "sqlite" then
    dialect = "postgresql"
  end
  return { name = vim.fs.basename(root), dialect = dialect }
end

M.topics = {
  { id = "formatter", key = "f", label = ".sql-formatter.json", default = "postgresql", core = true },
  { id = "compose", key = "c", label = "compose.yaml (database)", default = "postgres", alts = { "docker-compose.yml", "docker-compose.yaml" } },
  { id = "editorconfig", key = "e", label = ".editorconfig", default = "sql", core = true },
  { id = "ci", key = "y", label = "GitHub Actions CI", default = "github", alts = { ".github/workflows/ci.yaml" } },
}

return M
