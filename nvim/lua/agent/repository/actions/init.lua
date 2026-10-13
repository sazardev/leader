-- ── REPOSITORY level action registry ─────────────────────────────────────────
-- Persistence adapters (SQL repositories, in-memory...): built against a port, a table and a
-- sibling example (agent/repository/contracts). Same contract and same pipeline as agent/actions.
local M = {}

local NAMES = { "port", "implement", "review" }

---@type table<string, table>
local cache = {}

---@param name string
---@return table
function M.get(name)
  if not cache[name] then
    local action = require("agent.repository.actions." .. name)
    action.short = name
    action.name = "repo_" .. name
    cache[name] = action
  end
  return cache[name]
end

---@return table[]
function M.list()
  return vim.tbl_map(M.get, NAMES)
end

return M
