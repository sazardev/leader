-- Docker setup (<leader>DS): Dockerfile, compose.yaml, .dockerignore, hadolint, .editorconfig. Filled from
-- the folder's name or the existing files.
local M = { name = "Docker" }

---@param dir string
---@return string
function M.root(dir)
  return vim.fs.root(dir, function(name)
    return name == "Dockerfile" or name == "compose.yaml" or name == "docker-compose.yml" or name == "docker-compose.yaml"
  end) or vim.fs.root(dir, ".git") or dir
end

---@param root string
---@return table<string, string>
function M.vars(root)
  local name = vim.fs.basename(root)
  return { name = name }
end

M.topics = {
  { id = "dockerfile", key = "d", label = "Dockerfile", default = "alpine", alts = { "Dockerfile.prod", "dockerfile" } },
  { id = "compose", key = "c", label = "compose.yaml", default = "stack", alts = { "docker-compose.yml", "docker-compose.yaml" } },
  { id = "dockerignore", key = "i", label = ".dockerignore", default = "generic", core = true },
  { id = "hadolint", key = "h", label = "hadolint config", default = "standard", alts = { ".hadolint.yml", ".hadolint.yaml" } },
  { id = "editorconfig", key = "e", label = ".editorconfig", default = "docker", core = true },
}

function M.hint(topic)
  if topic.id == "hadolint" then
    return "run `hadolint Dockerfile` or add it to CI"
  elseif topic.id == "compose" then
    return "run `docker compose up -d`"
  end
end

return M
