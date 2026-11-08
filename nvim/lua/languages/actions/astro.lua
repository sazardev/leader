-- ── Astro actions (dev/build + project setup) ────────────────────────────────
local actions = require "utils.actions"
local log = require "utils.log"
local project = require "utils.project"
local terminal = require "utils.terminal"

local function at_root(fn)
  return function()
    local root = project.root { "package.json", ".git" }
    if vim.fs.basename(root) == "" or vim.fn.isdirectory(root) == 0 then
      return log.warn "No package.json found"
    end
    fn(root)
  end
end

local function pm_run(script)
  return at_root(function(root)
    local pm = "npm"
    if project.has(root, "pnpm-lock.yaml") then
      pm = "pnpm"
    elseif project.has(root, "bun.lock") or project.has(root, "bun.lockb") then
      pm = "bun"
    elseif project.has(root, "yarn.lock") then
      pm = "yarn"
    end
    terminal.run(("%s run %s"):format(pm, script), root)
  end)
end

local maps = {
  { "d", "dev (astro dev)", pm_run "dev" },
  { "b", "build (astro build)", pm_run "build" },
  { "p", "preview", pm_run "preview" },
  { "f", "format", actions.format },
}
return vim.list_extend(maps, require("langsetup").maps "astro")
