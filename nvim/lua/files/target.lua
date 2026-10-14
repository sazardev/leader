-- ── File operations: what an operation acts on ───────────────────────────────
-- In the tree it is the row under the cursor (a file or a folder); anywhere else, the file of the current buffer. So the
-- same keys work from both places.
local paths = require "files.paths"

local M = {}

---@class FilesTarget
---@field path string       absolute
---@field is_dir boolean
---@field in_tree boolean   it came from the tree (nvim-tree)
---@field root boolean      it is the tree's root (cannot be renamed or deleted from here)

---@return FilesTarget?
function M.resolve()
  if vim.bo.filetype == "NvimTree" then
    local ok, api = pcall(require, "nvim-tree.api")
    local node = ok and api.tree.get_node_under_cursor() or nil
    if not node or not node.absolute_path then
      return nil
    end
    return {
      path = vim.fs.normalize(node.absolute_path),
      is_dir = node.type == "directory",
      in_tree = true,
      root = node.parent == nil or node.name == "..",
    }
  end
  if vim.bo.buftype ~= "" then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(0)
  if name == "" then
    return nil
  end
  return { path = vim.fs.normalize(name), is_dir = false, in_tree = false, root = false }
end

--- Folder where a new thing goes: the folder itself, the file's folder, or the project when there is nothing
---@param target FilesTarget?
---@return string
function M.base(target)
  if not target then
    return vim.fn.getcwd()
  end
  return target.is_dir and target.path or vim.fs.dirname(target.path)
end

--- Shown name of the target relative to the project
---@param target FilesTarget
---@return string
function M.label(target)
  return paths.display(target.path, vim.fn.getcwd()) .. (target.is_dir and "/" or "")
end

return M
