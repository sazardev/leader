-- ── Desktop app: what it remembers ───────────────────────────────────────────
-- One small JSON file in the state folder (stdpath("state")/leader-gui.json): the
-- welcome/setup having been seen, the toolbar's choices. Read and written whole;
-- `update` merges a table into it.
local M = {}

M.FILE = vim.fn.stdpath "state" .. "/leader-gui.json"

---@return table
function M.read()
  local f = io.open(M.FILE)
  if not f then
    return {}
  end
  local ok, data = pcall(vim.json.decode, f:read "*a")
  f:close()
  return ok and type(data) == "table" and data or {}
end

---@param data table
function M.write(data)
  vim.fn.mkdir(vim.fs.dirname(M.FILE), "p")
  local f = io.open(M.FILE, "w")
  if f then
    f:write(vim.json.encode(data))
    f:close()
  end
end

--- Merges `patch` into what is saved (tables merge key by key, lists are replaced).
---@param patch table
---@return table the new state
function M.update(patch)
  local data = vim.tbl_deep_extend("force", M.read(), patch)
  M.write(data)
  return data
end

return M
