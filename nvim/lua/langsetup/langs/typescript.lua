-- TypeScript / JavaScript setup (<leader>tS): tsconfig, biome or eslint + prettier, vitest, Docker, CI, .nvmrc,
-- .editorconfig. Filled from package.json (name, engines.node) and the lockfile (package manager).
local read = function(path)
  return require("utils.project").read(path)
end

local M = { name = "TypeScript" }

---@param dir string
---@return string
function M.root(dir)
  return vim.fs.root(dir, "package.json") or vim.fs.root(dir, ".git") or dir
end

--- The package manager and its commands, from the lockfile (pure but for the stat)
---@param root string
---@return table<string, string>
function M.manager(root)
  local function has(f)
    return vim.uv.fs_stat(root .. "/" .. f) ~= nil
  end
  if has "pnpm-lock.yaml" then
    return { pm = "pnpm", install = "pnpm install --frozen-lockfile", run = "pnpm run", exec = "pnpm exec" }
  elseif has "bun.lock" or has "bun.lockb" then
    return { pm = "bun", install = "bun install --frozen-lockfile", run = "bun run", exec = "bunx" }
  elseif has "yarn.lock" then
    return { pm = "yarn", install = "yarn install --immutable", run = "yarn run", exec = "yarn" }
  end
  return { pm = "npm", install = "npm ci", run = "npm run", exec = "npx" }
end

---@param root string
---@return table<string, string>
function M.vars(root)
  local ok, pkg = pcall(vim.json.decode, read(root .. "/package.json") or "")
  pkg = ok and type(pkg) == "table" and pkg or {}
  local node = (read(root .. "/.nvmrc") or ""):match "(%d+)"
    or (type(pkg.engines) == "table" and tostring(pkg.engines.node or ""):match "(%d+)")
    or "22"
  local m = M.manager(root)
  return {
    name = type(pkg.name) == "string" and pkg.name or vim.fs.basename(root),
    node = node,
    pm = m.pm,
    install = m.install,
    run = m.run,
    exec = m.exec,
  }
end

M.topics = {
  { id = "tsconfig", key = "t", label = "tsconfig", default = "node", core = true },
  { id = "biome", key = "b", label = "Biome (lint + format)", default = "recommended", alts = { "biome.jsonc" } },
  {
    id = "eslint",
    key = "l",
    label = "ESLint (typescript-eslint)",
    default = "typescript",
    alts = { "eslint.config.mjs", "eslint.config.ts", ".eslintrc.json", ".eslintrc.js" },
  },
  {
    id = "prettier",
    key = "f",
    label = "Prettier",
    default = "standard",
    alts = { ".prettierrc", "prettier.config.js" },
  },
  {
    id = "vitest",
    key = "v",
    label = "Vitest config",
    default = "node",
    alts = { "vitest.config.js", "vitest.config.mts" },
  },
  { id = "docker", key = "d", label = "Dockerfile", default = "node" },
  { id = "dockerignore", key = "i", label = ".dockerignore", default = "node" },
  { id = "ci", key = "c", label = "GitHub Actions CI", default = "github", alts = { ".github/workflows/ci.yaml" } },
  { id = "nvmrc", key = "n", label = ".nvmrc", default = "lts", core = true },
  { id = "editorconfig", key = "e", label = ".editorconfig", default = "web", core = true },
}

function M.hint(topic)
  if topic.id == "biome" then
    return "add it: `bun add -d @biomejs/biome` (or npm/pnpm); it formats on save where a biome.json is"
  elseif topic.id == "eslint" then
    return "add it: eslint @eslint/js typescript-eslint as dev dependencies"
  elseif topic.id == "vitest" then
    return "add vitest as a dev dependency; <leader>tm runs the test under the cursor"
  end
end

return M
