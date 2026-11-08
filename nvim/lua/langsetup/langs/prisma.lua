-- Prisma setup (<leader>eS): prisma/schema.prisma (postgres/sqlite), compose.yaml, .editorconfig, CI. Filled from
-- the existing schema's datasource provider or the folder's name.
local read = function(path)
  return require("utils.project").read(path)
end

local M = { name = "Prisma" }

---@param dir string
---@return string
function M.root(dir)
  return vim.fs.root(dir, function(name)
    return name == "schema.prisma" or name == "package.json"
  end) or vim.fs.root(dir, ".git") or dir
end

---@param root string
---@return table<string, string>
function M.vars(root)
  local schema = read(root .. "/prisma/schema.prisma") or ""
  local provider = schema:match 'provider%s*=%s*"([^"]+)"' or "postgresql"
  local ok, pkg = pcall(vim.json.decode, read(root .. "/package.json") or "")
  local name = (ok and type(pkg) == "table" and pkg.name) or vim.fs.basename(root)
  return { name = name, provider = provider }
end

M.topics = {
  { id = "schema", key = "s", label = "prisma/schema.prisma", default = "postgres", core = true },
  { id = "compose", key = "c", label = "compose.yaml (database)", default = "postgres", alts = { "docker-compose.yml", "docker-compose.yaml" } },
  { id = "editorconfig", key = "e", label = ".editorconfig", default = "sql", core = true },
  { id = "ci", key = "y", label = "GitHub Actions CI", default = "github", alts = { ".github/workflows/ci.yaml" } },
}

function M.hint(topic)
  if topic.id == "schema" then
    return "generate with `npx prisma generate` (or pnpm dlx prisma generate)"
  end
end

return M
