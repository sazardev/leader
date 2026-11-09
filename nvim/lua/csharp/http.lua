-- ── HTTP test file (<leader>ch) ─────────────────────────────────────────────
-- Reads `Program.cs` next to the .csproj, takes its `MapGet/MapPost/…` routes and writes `requests.http`
-- (Rider/JetBrains format, base URL from the first launch profile): creates it once, never overwrites, opens
-- it, and fires the GET routes with curl in a separate `http test` terminal — never the terminal the app runs
-- in (POST/PUT/DELETE go in the file with an empty JSON body for you to fire by hand — not idempotent).
local proj = require "utils.csharpproj"
local http = require "utils.csharphttp"
local log = require "utils.log"

local M = {}

--- Creates/opens `requests.http` for `project_path` and fires its GET routes (disk + terminal, pure parts tested)
---@param project_path string the .csproj
function M.open_for_project(project_path)
  local dir = vim.fs.dirname(project_path)
  local name = vim.fs.basename(project_path):gsub("%.csproj$", "")
  local prog_path = dir .. "/Program.cs"
  if vim.uv.fs_stat(prog_path) == nil then
    return log.warn "C#: no Program.cs next to the .csproj (only minimal APIs are read; controllers need a .http by hand)"
  end
  local routes = http.routes(proj.read(prog_path))
  if #routes == 0 then
    return log.warn "C#: no MapGet/MapPost routes in Program.cs"
  end
  local base = http.base_url(proj.read(dir .. "/Properties/launchSettings.json") or "", "http://localhost:5000")
  local target = dir .. "/requests.http"
  if vim.uv.fs_stat(target) == nil then
    local f = io.open(target, "w")
    if not f then
      return log.warn "C#: cannot write requests.http"
    end
    f:write(http.render(base, routes, name))
    f:close()
    log.info(("C#: %s created (%d routes, base %s)"):format("requests.http", #routes, base))
  else
    log.info "C#: requests.http already exists (opened, not overwritten)"
  end
  vim.cmd.edit(vim.fn.fnameescape(target))
  local gets = vim.tbl_filter(function(r)
    return r.method == "Get" or r.method == "Delete"
  end, routes)
  if #gets == 0 then
    return log.info "C#: no GET routes to fire (POST/PUT go by hand from requests.http)"
  end
  local curls = vim.tbl_map(function(r)
    return http.curl(base, r)
  end, gets)
  require("utils.terminal").run_in("http test", table.concat(curls, " ; "), dir)
  log.info "C#: fired the GET routes in the `http test` terminal (start the app first with <leader>cr if they refuse connection)"
end

return M
