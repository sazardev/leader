-- ── DDD action registry ──────────────────────────────────────────────────────
-- Same contract as agent/actions (see there), in a SEPARATE registry: it is another feature, with its menu
-- (<leader>aD) and its own context (`ddd`). They run through the same pipeline: same experience
-- (inline diff, findings, window, history and cost).
local M = {}

local NAMES = { "implement", "review", "fix", "missing", "ask" }

---@type table<string, table>
local cache = {}

---@param name string
---@return table
function M.get(name)
  if not cache[name] then
    local action = require("agent.ddd.actions." .. name)
    action.short = name
    action.name = "ddd_" .. name -- history and the spend report tell them apart from the normal ones
    cache[name] = action
  end
  return cache[name]
end

---@return table[]
function M.list()
  return vim.tbl_map(M.get, NAMES)
end

return M
