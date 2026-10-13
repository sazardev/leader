-- ── Presenter registry ───────────────────────────────────────────────────────
-- A presenter decides what the result does in the editor. Contract:
--   stream(job)          (optional) partial text in job.partial, while it arrives
--   done(job, result)    final result; (optionally) returns a short summary
--   release(job)         (optional) cancellation/failure: release whatever it has set up
-- `action.output` picks the presenter. Add one: file + NAMES.
local M = {}

local NAMES = { "replace", "findings", "text" }

---@type table<string, table>
local cache = {}

---@param kind string
---@return table
function M.get(kind)
  if not vim.tbl_contains(NAMES, kind) then
    error("agent: unknown presenter '" .. tostring(kind) .. "'")
  end
  if not cache[kind] then
    cache[kind] = require("agent.output." .. kind)
  end
  return cache[kind]
end

return M
