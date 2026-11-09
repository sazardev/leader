-- ── Noodle collection (<leader>cNo) ─────────────────────────────────────────
-- Generates a Noodle collection (`noodle/`: `settings.yml`, `.environments/local.env`, one `.yml` request per
-- `MapGet/MapPost/…` route of `Program.cs`) next to the .csproj — files that exist are never overwritten — and
-- opens it in the Noodle TUI in its own `noodle` terminal (never the app's). From there: send requests, run the
-- whole collection (`noodle collection run`), or automate in CI. Needs the `noodle` binary on PATH.
local proj = require "utils.csharpproj"
local http = require "utils.csharphttp"
local noodle = require "utils.csharproodle"
local log = require "utils.log"

local M = {}

--- Overridable in tests (hermetic: the binary may not exist on the test machine)
function M.has_noodle()
  return vim.fn.executable "noodle" == 1
end

---@param dir string
---@param file string
---@param text string
---@return boolean written?
local function write_once(dir, file, text)
  local target = dir .. "/" .. file
  if vim.uv.fs_stat(target) ~= nil then
    return false
  end
  vim.fn.mkdir(vim.fs.dirname(target), "p")
  local f = io.open(target, "w")
  if not f then
    log.warn(("C#: cannot write %s"):format(file))
    return false
  end
  f:write(text)
  f:close()
  return true
end

--- Creates (never overwrites) and opens the Noodle collection of `project_path`
---@param project_path string the .csproj
function M.open_collection(project_path)
  local dir = vim.fs.dirname(project_path)
  local name = vim.fs.basename(project_path):gsub("%.csproj$", "")
  local prog_path = dir .. "/Program.cs"
  if vim.uv.fs_stat(prog_path) == nil then
    return log.warn "C#: no Program.cs next to the .csproj (only minimal APIs are read)"
  end
  local routes = http.routes(proj.read(prog_path))
  if #routes == 0 then
    return log.warn "C#: no MapGet/MapPost routes in Program.cs"
  end
  local base = http.base_url(proj.read(dir .. "/Properties/launchSettings.json") or "", "http://localhost:5000")
  local col = dir .. "/noodle"
  local made = 0
  if write_once(col, "settings.yml", noodle.settings_yml(name)) then
    made = made + 1
  end
  if write_once(col, ".environments/local.env", noodle.env_file(base)) then
    made = made + 1
  end
  for _, r in ipairs(routes) do
    if
      write_once(col, noodle.filename(r.method, r.route), noodle.request_yml(r.method, r.route, http.sample(r.route)))
    then
      made = made + 1
    end
  end
  if made > 0 then
    log.info(("C#: noodle/ ready (%d files, base %s)"):format(made, base))
  else
    log.info "C#: noodle/ already exists (opened, not overwritten)"
  end
  if not M.has_noodle() then
    return log.warn "C#: `noodle` is not on PATH (brew install noodle, or https://noodlerest.dev/docs/getting-started/installation/)"
  end
  local term = require "utils.terminal"
  local existing = term.named "noodle"
  if existing and term.busy(existing) then
    -- the TUI is already running there: just go to it instead of typing a second launch into it
    term.focus_term(existing)
    return log.info "C#: Noodle is already open below"
  end
  term.run_in("noodle", ("noodle --collection %s --env local"):format(vim.fn.shellescape(col)), dir)
  log.info "C#: Noodle TUI in the `noodle` terminal (send requests, or `noodle collection run` for CI)"
end

return M
