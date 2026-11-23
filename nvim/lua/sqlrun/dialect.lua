-- ── A project's dialect, when you want to say it out loud ──────────────────────
-- Normally the dialect comes from the connection (a .db file, DATABASE_URL...). When there is none, or detection guesses
-- wrong, this is the quick way to say "this project is sqlite": <leader>QD. It drives the keyword source, SQLFluff and
-- sql-formatter at once. sqls still needs a real connection to know the tables. Per project, stored in the state dir.
local M = {}

---@return string
local function path()
  return vim.fn.stdpath "state" .. "/sqlrun-dialect.json"
end

local function read()
  local text = require("utils.project").read(path())
  if not text or text == "" then
    return {}
  end
  local ok, data = pcall(vim.json.decode, text)
  return ok and type(data) == "table" and data or {}
end

local function write(data)
  vim.fn.mkdir(vim.fs.dirname(path()), "p")
  local f = io.open(path(), "w")
  if f then
    f:write(vim.json.encode(data))
    f:close()
    pcall(vim.uv.fs_chmod, path(), 384) -- 0600, like the other sqlrun state
  end
end

--- Completion asks for the dialect on every keystroke: keep it in memory for a moment (3 s, like connections.of).
---@type table<string, { at: integer, id: string? }>
local cache = {}

--- The dialect forced for a project, canonical id or nil for "from the connection"
---@param root string
---@return string?
function M.get(root)
  local hit = cache[root]
  if hit and vim.uv.now() - hit.at < 3000 then
    return hit.id
  end
  local id = read()[root]
  local dialect = type(id) == "string" and require("sqlrun.dialects").get(id) or nil
  cache[root] = { at = vim.uv.now(), id = dialect and dialect.id or nil }
  return cache[root].id
end

---@param root string
---@param id string? nil or "auto" clears the override
---@return string? problem
function M.set(root, id)
  local data = read()
  if not id or id == "auto" then
    data[root] = nil
  else
    local dialect = require("sqlrun.dialects").get(id)
    if not dialect then
      return "unknown dialect: " .. tostring(id)
    end
    data[root] = dialect.id
  end
  write(data)
  cache[root] = nil
end

return M
