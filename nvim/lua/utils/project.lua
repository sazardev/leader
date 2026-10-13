-- ── Project / filesystem helpers ─────────────────────────────────────────────
local M = {}

--- Directory of the current buffer's file
---@return string
function M.file_dir()
  return vim.fn.expand "%:p:h"
end

--- Project root according to markers (or the file's directory)
---@param markers string[]
---@return string
function M.root(markers)
  return vim.fs.root(0, markers) or M.file_dir()
end

--- Does `name` exist inside `dir`?
---@param dir string
---@param name string
---@return boolean
function M.has(dir, name)
  return vim.uv.fs_stat(dir .. "/" .. name) ~= nil
end

--- Read a whole file; nil if it does not exist
---@param path string
---@return string?
function M.read(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read "*a"
  f:close()
  return content
end

return M
