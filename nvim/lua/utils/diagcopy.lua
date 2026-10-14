-- ── Copy diagnostics (<leader>xl / xf / xe) ──────────────────────────────────
-- The diagnostics as plain text to paste in a chat, an issue or a terminal: the cursor line's, this file's, or those of
-- every file the language servers have reported. One line each, compiler style
-- (`path:line:col: severity: message (source code)`). `format` is pure.
local M = {}

local SEVERITY = { "error", "warning", "info", "hint" }

---@class DiagCopyItem
---@field path string
---@field lnum integer   0-based
---@field col integer    0-based
---@field severity integer?
---@field source string?
---@field code any?
---@field message string

--- Plain text of the diagnostics, ordered by file and position
---@param items DiagCopyItem[]
---@return string
function M.format(items)
  local sorted = vim.list_slice(items)
  table.sort(sorted, function(a, b)
    if a.path ~= b.path then
      return a.path < b.path
    end
    if a.lnum ~= b.lnum then
      return a.lnum < b.lnum
    end
    return a.col < b.col
  end)
  local out = {}
  for _, d in ipairs(sorted) do
    local tags = vim.tbl_filter(function(x)
      return x ~= ""
    end, { d.source or "", d.code ~= nil and tostring(d.code) or "" })
    local message = vim.trim(d.message):gsub("\n%s*", "\n  ")
    out[#out + 1] = ("%s:%d:%d: %s: %s%s"):format(
      d.path,
      d.lnum + 1,
      d.col + 1,
      SEVERITY[d.severity or 1] or "error",
      message,
      #tags > 0 and (" (" .. table.concat(tags, " ") .. ")") or ""
    )
  end
  return table.concat(out, "\n")
end

---@param d vim.Diagnostic
---@return DiagCopyItem
local function item(d)
  local name = vim.api.nvim_buf_get_name(d.bufnr)
  return {
    path = name == "" and "[No Name]" or vim.fn.fnamemodify(name, ":."),
    lnum = d.lnum,
    col = d.col,
    severity = d.severity,
    source = d.source,
    code = d.code,
    message = d.message,
  }
end

---@param scope "line"|"file"|"all"
---@return DiagCopyItem[]
function M.collect(scope)
  local list
  if scope == "line" then
    list = vim.diagnostic.get(0, { lnum = vim.api.nvim_win_get_cursor(0)[1] - 1 })
  elseif scope == "file" then
    list = vim.diagnostic.get(0)
  else
    list = vim.diagnostic.get(nil)
  end
  return vim.tbl_map(item, list)
end

local WHERE = { line = "on this line", file = "in this file", all = "in the project" }

---@param scope "line"|"file"|"all"
function M.copy(scope)
  local items = M.collect(scope)
  if #items == 0 then
    return require("utils.log").info("No diagnostics " .. WHERE[scope])
  end
  local text = M.format(items)
  vim.fn.setreg("+", text)
  vim.fn.setreg('"', text)
  require("utils.log").info(("Copied %d diagnostic%s %s"):format(#items, #items == 1 and "" or "s", WHERE[scope]))
end

return M
