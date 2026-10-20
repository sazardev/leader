-- ── Code search: the index on disk ───────────────────────────────────────────
-- The per-file symbols of a project with the stamp (mtime+size) they were read at, so a new session starts from the last
-- one and only re-reads what changed: the first search of a session costs about what a repeated one does, not the
-- treesitter parse of every file. One JSON file per project in the state dir; written atomically, ignored when it is
-- from another format or another folder.
local settings = require("core.settings").search

local M = {}

--- Bump it when what `index.read` extracts changes: older files are then ignored and rebuilt.
M.FORMAT = 1

---@return string
local function dir()
  return settings.store_dir or (vim.fn.stdpath "state" .. "/codesearch")
end

---@param root string
---@return string
function M.path(root)
  return ("%s/%s.json"):format(dir(), vim.fn.sha256(root):sub(1, 16))
end

---@param root string
---@return table<string, { stamp: string, symbols: CodeSymbol[] }>? files nil when there is nothing usable
function M.load(root)
  if not settings.persist then
    return nil
  end
  local f = io.open(M.path(root), "rb")
  if not f then
    return nil
  end
  local text = f:read "*a"
  f:close()
  local ok, data = pcall(vim.json.decode, text)
  if not ok or type(data) ~= "table" or data.format ~= M.FORMAT or data.root ~= root or type(data.files) ~= "table" then
    return nil
  end
  return data.files
end

---@param root string
---@param files table<string, { stamp: string, symbols: CodeSymbol[] }>
---@return boolean saved
function M.save(root, files)
  if not settings.persist then
    return false
  end
  local ok, text = pcall(vim.json.encode, { format = M.FORMAT, root = root, files = files })
  if not ok then
    return false
  end
  pcall(vim.fn.mkdir, dir(), "p")
  local path = M.path(root)
  local tmp = ("%s.%d.tmp"):format(path, vim.uv.os_getpid())
  local f = io.open(tmp, "wb")
  if not f then
    return false
  end
  f:write(text)
  f:close()
  if not os.rename(tmp, path) then
    os.remove(tmp)
    return false
  end
  return true
end

---@param root string
function M.delete(root)
  os.remove(M.path(root))
end

return M
