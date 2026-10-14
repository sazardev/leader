-- ── File operations: where it will land ──────────────────────────────────────
-- The modal's picture of a destination: project root → … → folder, with the subfolders already there, and a mark on the
-- row where the new thing goes. (What nvim-tree's "new folder" modal drew, now shared by every file operation.)
local hl = require("utils.modal").hl

local M = {}

local MAX_CHILDREN = 6

---@param dir string  absolute folder
---@param mark string? text after the destination row
---@return (string|table[])[]
function M.lines(dir, mark)
  local root = vim.fn.getcwd()
  mark = mark or "   <- goes here"
  if dir:find(root, 1, true) ~= 1 then
    return { { { "Location:" } }, { { "  " }, { dir .. "/", hl.folder } } }
  end

  local parts = vim.split(dir:sub(#root + 2), "/", { plain = true, trimempty = true })
  local lines = { { { "Location:" } } }

  local root_line = { { "  " }, { vim.fn.fnamemodify(root, ":t") .. "/", hl.folder } }
  if #parts == 0 then
    vim.list_extend(root_line, { { mark, hl.mark } })
  end
  lines[#lines + 1] = root_line

  for i, part in ipairs(parts) do
    local line = {
      { ("  %s└── "):format(("   "):rep(i - 1)), hl.tree },
      { part .. "/", hl.folder },
    }
    if i == #parts then
      line[#line + 1] = { mark, hl.mark }
    end
    lines[#lines + 1] = line
  end

  local indent = ("  %s"):format(("   "):rep(#parts))
  local children = {}
  for name, kind in vim.fs.dir(dir, { depth = 1 }) do
    if kind == "directory" then
      children[#children + 1] = name
    end
  end
  table.sort(children)
  for i, name in ipairs(children) do
    if i > MAX_CHILDREN then
      lines[#lines + 1] = { { indent .. "…", hl.muted } }
      break
    end
    lines[#lines + 1] = { { indent .. "├── ", hl.tree }, { name .. "/", hl.folder } }
  end
  return lines
end

return M
