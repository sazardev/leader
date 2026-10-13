-- ── TEST action registry (<leader>aT) ─────────────────────────────────────────
-- Same contract and pipeline as agent/actions, plus the hooks the pipeline recognizes:
--   retarget(subject)   the result goes to the test file, not to the function (agent/tests/target.lua)
--   merge(code, target) the model returns only what is new; it is joined at the end of the file
--   reveal              opens the destination to the side to accept/reject there
--   prepare(target, cb) prior work WITHOUT a model (running the test); if there is nothing to ask, 0 tokens
local M = {}

local NAMES = { "write", "mock", "fix" }

---@type table<string, table>
local cache = {}

---@param name string
---@return table
function M.get(name)
  if not cache[name] then
    local action = require("agent.tests.actions." .. name)
    action.short = name
    action.name = "test_" .. name
    cache[name] = action
  end
  return cache[name]
end

---@return table[]
function M.list()
  return vim.tbl_map(M.get, NAMES)
end

return M
