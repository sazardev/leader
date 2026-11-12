-- ── `go test` command line ───────────────────────────────────────────────────
-- ONE builder for the test actions of <leader>g (l = the file's package, m/R/c =
-- ./...). The actions run through langtest (`-json`, one event per test), so the
-- statusline and the quickfix know what happened; this module only builds the
-- argv and keeps `settings.go.test.args` (`-count=1`, `-tags=integration`…).
-- `verbose` now filters the output shown by `O`, since `-json` already carries
-- every test's events.
--
-- The settings are read on every call (not when this module loads), so a toggle
-- in the settings panel (`<leader>Sp` → Go) applies to the next run without a
-- restart.
local settings = require "core.settings"

local M = {}

--- argv of `go test` for `scope` (`./...` or the package's relative folder).
--- Flags go BEFORE the scope: `go test -race ./...`, never `./... -race`.
---@param flags string[]? build/test flags of the action (`-race`, `-cover`…)
---@param scope string package argument (`./...`, `.`, `./cmd/api`…)
---@param opts { json?: boolean }? json = langtest's one-event-per-test mode
---@return string[]
function M.args(flags, scope, opts)
  local cfg = settings.go.test or {}
  local args = { "go", "test" }
  if opts and opts.json then
    args[#args + 1] = "-json"
  elseif cfg.verbose ~= false then
    args[#args + 1] = "-v"
  end
  vim.list_extend(args, flags or {})
  vim.list_extend(args, cfg.args or {})
  args[#args + 1] = scope
  return args
end

--- `go test` line for `scope`, for a shell (`<leader>g` used to run it in the terminal).
--- Flags go BEFORE the scope: `go test -v -race ./...`, never `./... -race`.
---@param flags string[]? build/test flags of the action (`-race`, `-cover`…)
---@param scope string package argument (`./...`, `.`, `./cmd/api`…)
---@return string
function M.command(flags, scope)
  local args = M.args(flags, scope)
  args[#args] = vim.fn.shellescape(scope)
  return table.concat(args, " ")
end

return M
