-- ── SERVICE level action registry ────────────────────────────────────────────
-- Application services / use cases: they orchestrate the domain and call the ports. Same contract and same pipeline
-- as agent/actions; the level's own context is `ports` (the interfaces the service can call).
local M = {}

local NAMES = { "implement", "review" }

---@type table<string, table>
local cache = {}

---@param name string
---@return table
function M.get(name)
  if not cache[name] then
    local action = require("agent.service.actions." .. name)
    action.short = name
    action.name = "service_" .. name
    cache[name] = action
  end
  return cache[name]
end

---@return table[]
function M.list()
  return vim.tbl_map(M.get, NAMES)
end

return M
