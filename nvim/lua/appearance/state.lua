-- ── Persistent appearance state ──────────────────────────────────────────────
-- Two files, both outside the repo (machine state):
--   · choice   (stdpath "state"):  which theme the user wants.
--   · compiled (next to the base46 cache): which theme the highlight cache
--     ACTUALLY contains and with which terminal signature. It lives with the cache so
--     they never get out of sync (if one is deleted, the other goes too).
local M = {}

---@param path string
---@return table
local function read_json(path)
  local f = io.open(path, "r")
  if not f then
    return {}
  end
  local ok, data = pcall(vim.json.decode, f:read "*a")
  f:close()
  return ok and type(data) == "table" and data or {}
end

---@param path string
---@param data table
local function write_json(path, data)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = io.open(path, "w")
  if f then
    f:write(vim.json.encode(data))
    f:close()
  end
end

local function choice_path()
  return vim.fn.stdpath "state" .. "/appearance.json"
end

local function compiled_path()
  return vim.g.base46_cache .. "appearance.json"
end

---@return { theme: string? }
function M.read_choice()
  return read_json(choice_path())
end

---@param theme string
function M.write_choice(theme)
  write_json(choice_path(), { theme = theme })
end

---@return { theme: string?, signature: string? }
function M.read_compiled()
  return read_json(compiled_path())
end

---@param data { theme: string, signature: string? }
function M.write_compiled(data)
  write_json(compiled_path(), data)
end

return M
