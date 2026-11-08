-- Astro setup (<leader>oS): astro.config, tsconfig, prettier, CI, Docker, .editorconfig. Filled from
-- package.json (name, node, package manager) and the lockfile.
local read = function(path)
  return require("utils.project").read(path)
end

local M = { name = "Astro" }

---@param dir string
---@return string
function M.root(dir)
  return vim.fs.root(dir, function(name)
    return name == "package.json" or name:match "^astro.config" ~= nil
  end) or vim.fs.root(dir, ".git") or dir
end

---@param root string
---@return table<string, string>
function M.vars(root)
  local ok, pkg = pcall(vim.json.decode, read(root .. "/package.json") or "")
  pkg = ok and type(pkg) == "table" and pkg or {}
  local node = (read(root .. "/.nvmrc") or ""):match "(%d+)"
    or (type(pkg.engines) == "table" and tostring(pkg.engines.node or ""):match "(%d+)")
    or "22"
  local function has(f)
    return vim.uv.fs_stat(root .. "/" .. f) ~= nil
  end
  local pm = "npm"
  if has "pnpm-lock.yaml" then
    pm = "pnpm"
  elseif has "bun.lock" or has "bun.lockb" then
    pm = "bun"
  elseif has "yarn.lock" then
    pm = "yarn"
  end
  local install = ({ pnpm = "pnpm install --frozen-lockfile", bun = "bun install --frozen-lockfile", yarn = "yarn install --immutable", npm = "npm ci" })[pm]
  local run = ({ pnpm = "pnpm run", bun = "bun run", yarn = "yarn run", npm = "npm run" })[pm]
  local exec = ({ pnpm = "pnpm exec", bun = "bunx", yarn = "yarn", npm = "npx" })[pm]
  return {
    name = type(pkg.name) == "string" and pkg.name or vim.fs.basename(root),
    node = node,
    pm = pm,
    install = install,
    run = run,
    exec = exec,
  }
end

M.topics = {
  { id = "astroconfig", key = "a", label = "astro.config", default = "standard", core = true, alts = { "astro.config.mjs", "astro.config.ts" } },
  { id = "tsconfig", key = "t", label = "tsconfig", default = "astro", core = true },
  { id = "prettier", key = "f", label = "Prettier", default = "standard", alts = { ".prettierrc", "prettier.config.js" } },
  { id = "editorconfig", key = "e", label = ".editorconfig", default = "web", core = true },
  { id = "docker", key = "d", label = "Dockerfile", default = "node" },
  { id = "dockerignore", key = "i", label = ".dockerignore", default = "node" },
  { id = "ci", key = "c", label = "GitHub Actions CI", default = "github", alts = { ".github/workflows/ci.yaml" } },
  { id = "nvmrc", key = "n", label = ".nvmrc", default = "lts", core = true },
}

return M
