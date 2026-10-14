-- ── Saved choices of the settings panel ──────────────────────────────────────
-- What you pick in <leader>Sp is kept outside the repo (`stdpath("state")/prefs.json`) as a flat map from the setting's
-- path to its value (`{"ui.motion": false}`), and wins over `settings.lua` and `local.lua` the next time nvim starts.
-- Pure apart from the file: the path helpers are tested in scripts/test-prefs.lua.
local M = {}

---@return string
function M.path()
  return vim.fn.stdpath "state" .. "/prefs.json"
end

---@return table<string, any>
function M.read()
  local f = io.open(M.path(), "r")
  if not f then
    return {}
  end
  local ok, data = pcall(vim.json.decode, f:read "*a")
  f:close()
  return ok and type(data) == "table" and data or {}
end

---@param data table<string, any>
function M.write(data)
  vim.fn.mkdir(vim.fs.dirname(M.path()), "p")
  local f = io.open(M.path(), "w")
  if f then
    f:write(vim.json.encode(data))
    f:close()
  end
end

--- Forgets every saved choice
function M.clear()
  os.remove(M.path())
end

---@param tbl table
---@param path string  "ui.motion"
---@return any
function M.get(tbl, path)
  local node = tbl
  for key in path:gmatch "[^.]+" do
    if type(node) ~= "table" then
      return nil
    end
    node = node[key]
  end
  return node
end

--- Sets (or, with nil, removes) a dotted path, creating the tables on the way
---@param tbl table
---@param path string
---@param value any
function M.set(tbl, path, value)
  local keys = vim.split(path, ".", { plain = true })
  local node = tbl
  for i = 1, #keys - 1 do
    if type(node[keys[i]]) ~= "table" then
      node[keys[i]] = {}
    end
    node = node[keys[i]]
  end
  node[keys[#keys]] = value
end

--- The flat map as the nested table `core.settings` merges
---@param data table<string, any>
---@return table
function M.nest(data)
  local out = {}
  for path, value in pairs(data) do
    M.set(out, path, value)
  end
  return out
end

--- Saves one choice (nil forgets it)
---@param path string
---@param value any
function M.save(path, value)
  local data = M.read()
  data[path] = value
  M.write(data)
end

return M
