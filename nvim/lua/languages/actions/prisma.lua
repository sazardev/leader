-- ── Prisma actions (generate/migrate/studio + project setup) ────────────────
local log = require "utils.log"
local terminal = require "utils.terminal"

local function at_root(fn)
  return function()
    local root = (vim.fs.root(0, { "package.json", ".git" }))
    if not root then
      return log.warn "No package.json found"
    end
    fn(root)
  end
end

local maps = {
  {
    "g",
    "generate client",
    at_root(function(root)
      terminal.run("npx prisma generate", root)
    end),
  },
  {
    "m",
    "migrate dev",
    at_root(function(root)
      terminal.run("npx prisma migrate dev", root)
    end),
  },
  {
    "S",
    "studio",
    at_root(function(root)
      terminal.run("npx prisma studio", root)
    end),
  },
}
return vim.list_extend(maps, require("langsetup").maps "prisma")
