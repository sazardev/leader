-- ── Rename: all the variants in one place ────────────────────────────────────
--   file()    rename the word under the cursor in THIS buffer only (no LSP, no tokens)
--   project() rename across the project (GrugFar, prefilled, with preview)
--   symbol()  real LSP rename of the symbol (several files when it applies)
-- Global keys live together in core/keymaps/general.lua: <leader>rn / <leader>rN / <leader>rs.
local M = {}

--- Escape a name for the pattern side of :s
---@param s string
---@return string
function M.escape(s)
  return vim.fn.escape(s, "/\\")
end

--- Build the :s command that renames `old` to `new` in the whole buffer
---@param old string
---@param new string
---@return string
function M.command(old, new)
  local pat = M.escape(old)
  local repl = vim.fn.escape(new, "/\\&~")
  return ("%s/\\<%s\\>/%s/g"):format("%s", pat, repl)
end

--- Valid variable name? (letters, digits and _)
---@param s string
---@return boolean
function M.valid(s)
  return s:match("^[%w_]+$") ~= nil
end

--- Rename the word under the cursor in this file only
function M.file()
  local old = vim.fn.expand "<cword>"
  if old == "" then
    return require("utils.log").warn "Rename: put the cursor on the variable first"
  end
  require("utils.modal").input(
    { ("Rename '%s' in this file only:"):format(old) },
    { title = "Rename in file", default = old, confirm = "Rename" },
    function(new)
      new = vim.trim(new or "")
      if new == "" or new == old then
        return
      end
      if not M.valid(new) then
        return require("utils.log").warn "Rename: use only letters, digits and _"
      end
      local view = vim.fn.winsaveview()
      local ok, err = pcall(vim.cmd, "keepjumps " .. M.command(old, new))
      pcall(vim.fn.winrestview, view)
      if not ok then
        return require("utils.log").warn("Rename: " .. tostring(err):gsub("^.-:%s*", ""))
      end
      require("utils.log").info(("Rename: '%s' → '%s' (this file)"):format(old, new))
    end
  )
end

--- Rename across the whole project (GrugFar, prefilled with the word/selection)
function M.project()
  local ok, grug = pcall(require, "grug-far")
  if not ok then
    return require("utils.log").warn "Rename: grug-far is not installed"
  end
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    grug.with_visual_selection()
    return
  end
  local word = vim.fn.expand "<cword>"
  if word == "" then
    return require("utils.log").warn "Rename: put the cursor on the variable first"
  end
  grug.open { prefills = { search = word } }
end

--- Rename the symbol through the LSP (all its uses, several files when it applies).
--- Same as grn / <leader>ra, kept here so every rename lives together.
function M.symbol()
  local buf = vim.api.nvim_get_current_buf()
  if #vim.lsp.get_clients { bufnr = buf, method = "textDocument/rename" } == 0 then
    local names = vim.tbl_map(function(c)
      return c.name
    end, vim.lsp.get_clients { bufnr = buf })
    if #names == 0 then
      return require("utils.log").warn(("Rename: no LSP in this file (%s)"):format(vim.bo[buf].filetype))
    end
    return require("utils.log").warn(("Rename: %s is still starting or cannot rename"):format(table.concat(names, ", ")))
  end
  vim.lsp.buf.rename()
end

-- Backwards-compat alias (first version of this helper)
M.rename_in_file = M.file

return M
