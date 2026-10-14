-- ── File operations: what a change does to the editor ────────────────────────
-- After a file moves or goes away the open buffers, the language servers and the tree have to follow. Separate from
-- files/ops.lua so the file system part stays testable without an editor.
local paths = require "files.paths"

local M = {}

---@return integer[] listed buffers with a file name
local function named()
  return vim.tbl_filter(function(buf)
    return vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) ~= "" and vim.bo[buf].buftype == ""
  end, vim.api.nvim_list_bufs())
end

---@param old string
---@param new string
---@return table  the `files` of an LSP file-operation request
local function lsp_files(old, new)
  return { files = { { oldUri = vim.uri_from_fname(old), newUri = vim.uri_from_fname(new) } } }
end

--- Servers may want to edit imports before the move (tsserver does): asked before, applied before
---@param old string
---@param new string
function M.lsp_will_rename(old, new)
  for _, client in ipairs(vim.lsp.get_clients()) do
    if client:supports_method "workspace/willRenameFiles" then
      local ok, res = pcall(client.request_sync, client, "workspace/willRenameFiles", lsp_files(old, new), 1000, 0)
      if ok and res and res.result then
        pcall(vim.lsp.util.apply_workspace_edit, res.result, client.offset_encoding)
      end
    end
  end
end

---@param old string
---@param new string
function M.lsp_did_rename(old, new)
  for _, client in ipairs(vim.lsp.get_clients()) do
    if client:supports_method "workspace/didRenameFiles" then
      pcall(client.notify, client, "workspace/didRenameFiles", lsp_files(old, new))
    end
  end
end

--- The nvim-tree window (if it was ever opened) shows the change
function M.refresh_tree()
  if package.loaded["nvim-tree.api"] then
    pcall(function()
      require("nvim-tree.api").tree.reload()
    end)
  end
end

--- Buffers that were `old` (or inside it) now live at `new`: same buffer, same window, unsaved work kept
---@param old string
---@param new string
---@return integer count
function M.renamed(old, new)
  local count = 0
  for _, buf in ipairs(named()) do
    local target = paths.rebase(vim.fs.normalize(vim.api.nvim_buf_get_name(buf)), old, new)
    if target then
      local before = vim.api.nvim_buf_get_name(buf)
      local modified = vim.bo[buf].modified
      local lines = modified and vim.api.nvim_buf_get_lines(buf, 0, -1, false) or nil
      vim.api.nvim_buf_set_name(buf, target)
      -- setting a name leaves a ghost buffer with the old one: it would show in :ls and make the next save ask questions
      local ghost = vim.fn.bufnr("^" .. vim.fn.fnameescape(before) .. "$")
      if ghost ~= -1 and ghost ~= buf then
        pcall(vim.api.nvim_buf_delete, ghost, { force = true })
      end
      -- reload from the new place so the buffer knows that file is its own (otherwise the next save says "File exists");
      -- what was typed and never saved is put back on top
      vim.api.nvim_buf_call(buf, function()
        vim.cmd "silent! edit!"
      end)
      if lines then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.bo[buf].modified = true
      end
      count = count + 1
    end
  end
  return count
end

--- Open buffers of `path` (or inside it) with changes that were never saved
---@param path string
---@return integer
function M.unsaved_inside(path)
  local count = 0
  for _, buf in ipairs(named()) do
    if vim.bo[buf].modified and paths.inside(vim.fs.normalize(vim.api.nvim_buf_get_name(buf)), path) then
      count = count + 1
    end
  end
  return count
end

--- Buffers of something that is gone: their windows move to another buffer (or an empty one), then they are wiped
---@param path string
---@return integer count
function M.removed(path)
  local count = 0
  for _, buf in ipairs(named()) do
    if paths.inside(vim.fs.normalize(vim.api.nvim_buf_get_name(buf)), path) then
      for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        vim.api.nvim_win_call(win, function()
          local alt = vim.fn.bufnr "#"
          if alt ~= -1 and alt ~= buf and vim.bo[alt].buflisted and vim.api.nvim_buf_is_loaded(alt) then
            vim.api.nvim_win_set_buf(win, alt)
          else
            vim.cmd "enew"
          end
        end)
      end
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
      count = count + 1
    end
  end
  return count
end

return M
