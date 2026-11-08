-- ── Docker actions (build/up/down + project setup) ──────────────────────────
local log = require "utils.log"
local terminal = require "utils.terminal"

local function docker_run(cmd)
  return function()
    local root = (vim.fs.root(0, { "Dockerfile", "compose.yaml", "docker-compose.yml", ".git" }))
    if not root then
      return log.warn "No Dockerfile/compose found"
    end
    terminal.run(cmd, root)
  end
end

local maps = {
  { "b", "build image", docker_run "docker build -t app ." },
  { "u", "compose up -d", docker_run "docker compose up -d" },
  { "d", "compose down", docker_run "docker compose down" },
  { "l", "compose logs", docker_run "docker compose logs -f" },
}
return vim.list_extend(maps, require("langsetup").maps "docker")
