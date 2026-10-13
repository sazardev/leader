-- ── Registro de acciones del nivel REPOSITORY ────────────────────────────────
-- Adaptadores de persistencia (repositorios SQL, en memoria...): se construyen contra un puerto, una tabla y un
-- ejemplo hermano (agent/repository/contracts). Mismo contrato y mismo pipeline que agent/actions.
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
