-- ── `go test` command line ───────────────────────────────────────────────────
-- ONE builder for the test actions of <leader>g (l = the file's package, m/R/c =
-- ./...): all of them print every test's name and `t.Log` output, not only the
-- package result. `settings.go.test` decides it (`verbose`, default on) and
-- appends extra flags (`-count=1`, `-tags=integration`, `-short`…).
--
-- The settings are read on every call (not when this module loads), so a toggle
-- in the settings panel (`<leader>Sp` → Go) applies to the next run without a
-- restart.
local settings = require "core.settings"

local M = {}

--- `go test` line for `scope` (`./...` or the package's relative folder).
--- Flags go BEFORE the scope: `go test -v -race ./...`, never `./... -race`.
---@param flags string[]? build/test flags of the action (`-race`, `-cover`…)
---@param scope string package argument (`./...`, `.`, `./cmd/api`…)
---@return string
function M.command(flags, scope)
  local cfg = settings.go.test or {}
  local args = { "go", "test" }
  if cfg.verbose ~= false then
    args[#args + 1] = "-v"
  end
  vim.list_extend(args, flags or {})
  vim.list_extend(args, cfg.args or {})
  args[#args + 1] = vim.fn.shellescape(scope)
  return table.concat(args, " ")
end

return M
