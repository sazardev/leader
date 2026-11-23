-- ── Named queries of a project (<leader>Qv / <leader>QV) ───────────────────────
-- The queries worth running again, with a name you choose instead of a line in the history. One JSON in the state dir
-- (0600: a query can contain literals), per project. `add`/`remove` are pure so test-langs.lua can check them.
local M = {}

---@class SqlFavorite
---@field name string
---@field text string
---@field at integer

---@return string
local function path()
  return vim.fn.stdpath "state" .. "/sqlrun-favorites.json"
end

local function load_all()
  local text = require("utils.project").read(path())
  if not text or text == "" then
    return {}
  end
  local ok, data = pcall(vim.json.decode, text)
  return ok and type(data) == "table" and data or {}
end

local function save_all(data)
  vim.fn.mkdir(vim.fs.dirname(path()), "p")
  local f = io.open(path(), "w")
  if f then
    f:write(vim.json.encode(data))
    f:close()
    pcall(vim.uv.fs_chmod, path(), 384)
  end
end

--- The named queries of a project, newest first
---@param root string
---@return SqlFavorite[]
function M.load(root)
  local list = load_all()[root]
  return type(list) == "table" and list or {}
end

--- Adds or renames a query (pure): the same name replaces its text and comes back on top
---@param list SqlFavorite[]
---@param name string
---@param text string
---@param at integer?
---@return SqlFavorite[]
function M.add(list, name, text, at)
  local out = { { name = name, text = text, at = at or os.time() } }
  for _, item in ipairs(list or {}) do
    if item.name ~= name then
      out[#out + 1] = item
    end
  end
  return out
end

--- Removes by name (pure)
---@param list SqlFavorite[]
---@param name string
---@return SqlFavorite[], boolean
function M.remove(list, name)
  local out, found = {}, false
  for _, item in ipairs(list or {}) do
    if item.name == name then
      found = true
    else
      out[#out + 1] = item
    end
  end
  return out, found
end

---@param root string
---@param name string
---@param text string
function M.save(root, name, text)
  local data = load_all()
  data[root] = M.add(type(data[root]) == "table" and data[root] or {}, name, text)
  save_all(data)
end

---@param root string
---@param name string
---@return boolean
function M.forget(root, name)
  local data = load_all()
  local list, found = M.remove(type(data[root]) == "table" and data[root] or {}, name)
  if not found then
    return false
  end
  data[root] = list
  save_all(data)
  return true
end

return M
