-- ── TypeScript / JavaScript actions ──────────────────────────────────────────
-- Detects the package manager (pnpm/yarn/bun/npm) by lockfile and uses the
-- package.json scripts when they exist.
local actions = require "utils.actions"
local log = require "utils.log"
local project = require "utils.project"
local terminal = require "utils.terminal"

local MARKERS = { "package.json", ".git" }

---@return string pm, string root
local function package_manager()
  local root = project.root(MARKERS)
  if project.has(root, "pnpm-lock.yaml") then
    return "pnpm", root
  elseif project.has(root, "yarn.lock") then
    return "yarn", root
  elseif project.has(root, "bun.lockb") or project.has(root, "bun.lock") then
    return "bun", root
  end
  return "npm", root
end

---@param root string
---@return string[]
local function scripts(root)
  local content = project.read(root .. "/package.json")
  local ok, pkg = pcall(vim.json.decode, content or "")
  local names = ok and type(pkg) == "table" and type(pkg.scripts) == "table" and vim.tbl_keys(pkg.scripts) or {}
  table.sort(names)
  return names
end

--- Runs the package.json script if it exists; otherwise `fallback` (or warns).
local function script(name, fallback)
  return function()
    local pm, root = package_manager()
    if vim.tbl_contains(scripts(root), name) then
      return terminal.run(("%s run %s"):format(pm, name), root)
    end
    if fallback then
      return terminal.run(fallback, root)
    end
    log.warn(("package.json has no `%s` script"):format(name))
  end
end

local function pick_script()
  local pm, root = package_manager()
  local names = scripts(root)
  if #names == 0 then
    return log.warn "No scripts in package.json"
  end
  vim.ui.select(names, { prompt = pm .. " run" }, function(choice)
    if choice then
      terminal.run(("%s run %s"):format(pm, choice), root)
    end
  end)
end

local function pm_command(sub)
  return function()
    local pm, root = package_manager()
    terminal.run(pm .. " " .. sub, root)
  end
end

return {
  { "r", "run a package.json script (picker)", pick_script },
  { "d", "dev (script `dev`)", script "dev" },
  { "b", "build (script `build`)", script "build" },
  { "m", "test (package manager)", pm_command "test" },
  { "v", "lint (script `lint`, else eslint .)", script("lint", "npx --no-install eslint .") },
  { "c", "typecheck (tsc --noEmit)", actions.run("npx", "npx --no-install tsc --noEmit", MARKERS) },
  {
    "x",
    "eslint --fix (current file)",
    function()
      local _, root = package_manager()
      terminal.run("npx --no-install eslint --fix " .. vim.fn.shellescape(vim.fn.expand "%:p"), root)
    end,
  },
  { "f", "format", actions.format },
  { "o", "organize imports", actions.code_action "source.organizeImports" },
  { "i", "install dependencies", pm_command "install" },
}
