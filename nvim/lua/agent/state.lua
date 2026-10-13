-- ── Estado persistente del agente ────────────────────────────────────────────
-- Qué backend/modelo/esfuerzo dejaste elegido (stdpath("state")/agent.json), para
-- que sobreviva entre sesiones. Solo clave/valor; la política vive en selection.lua.
local M = {}

local PATH = vim.fn.stdpath "state" .. "/agent.json"

---@type table?
local cache

---@return table
local function read()
  if cache then
    return cache
  end
  cache = {}
  local f = io.open(PATH, "r")
  if f then
    local ok, data = pcall(vim.json.decode, f:read "*a")
    f:close()
    if ok and type(data) == "table" then
      cache = data
    end
  end
  return cache
end

---@param key string
---@return any
function M.get(key)
  return read()[key]
end

---@param key string
---@param value any
function M.set(key, value)
  read()[key] = value
  vim.fn.mkdir(vim.fn.fnamemodify(PATH, ":h"), "p")
  local f = io.open(PATH, "w")
  if f then
    f:write(vim.json.encode(cache))
    f:close()
  end
end

return M
