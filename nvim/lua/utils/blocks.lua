-- ── Block navigation (PageUp/PageDown, Home/End) ─────────────────────────────
-- Jumps from declaration to declaration (functions, methods, classes, structs/interfaces
-- in Go...) using treesitter's `textobjects` queries: the same definition as
-- `af`/`ac`. Anonymous functions inside another function (closures, callbacks) don't
-- count as a stop, so it doesn't halt in the middle of a body. Without parser/query
-- (nvim-tree, plain text...) it falls back to the key's native behaviour.
local scopes = require "agent.context.scopes"

local M = {}

---@class Block
---@field first integer row (0-based) where it starts
---@field last integer row (0-based) where it ends
---@field node TSNode
---@field kind "function"|"class"

--- Buffer blocks, sorted by start and without duplicates
---@param buf integer
---@return Block[]?
local function get_blocks(buf)
  local root, _, query = scopes.parse(buf)
  if not (root and query) then
    return nil
  end

  local found, fn_ids = {}, {}
  for id, node in query:iter_captures(root, buf, 0, -1) do
    local name = query.captures[id]
    if name == "function.outer" or name == "class.outer" then
      found[#found + 1] = { node = node, fn = name == "function.outer" }
      if name == "function.outer" then
        fn_ids[node:id()] = true
      end
    end
  end

  local seen, blocks = {}, {}
  for _, item in ipairs(found) do
    local nested = false
    if item.fn then
      local parent = item.node:parent()
      while parent do
        if fn_ids[parent:id()] then
          nested = true
          break
        end
        parent = parent:parent()
      end
    end
    local row, _, last, last_col = item.node:range()
    -- an end at column 0 includes the line break: the block ends on the previous row
    if last_col == 0 and last > row then
      last = last - 1
    end
    if not nested and not seen[row] then
      seen[row] = true
      blocks[#blocks + 1] = { first = row, last = last, node = item.node, kind = item.fn and "function" or "class" }
    end
  end
  table.sort(blocks, function(a, b)
    return a.first < b.first
  end)
  return blocks
end

--- Buffer blocks (nil if there is no parser or query); used by utils/docgen.lua
M.list = get_blocks

---@param row integer 0-based
local function go_to(row)
  vim.cmd "normal! m'"
  vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
  vim.cmd "normal! ^zz"
end

--- Move the cursor `count` blocks; `forward` = true goes down, false goes up
---@param forward boolean
function M.jump(forward)
  local count = vim.v.count1
  local blocks = get_blocks(vim.api.nvim_get_current_buf())

  if not blocks or #blocks == 0 then
    local key = vim.keycode(forward and "<PageDown>" or "<PageUp>")
    return vim.api.nvim_feedkeys(count .. key, "n", false)
  end

  local cur = vim.api.nvim_win_get_cursor(0)[1] - 1
  local rows = vim.tbl_map(function(b)
    return b.first
  end, blocks)
  local target
  if forward then
    local after = vim.tbl_filter(function(r)
      return r > cur
    end, rows)
    -- no more blocks below: go to the end of the file
    target = after[math.min(count, #after)] or vim.api.nvim_buf_line_count(0) - 1
  else
    local before = vim.tbl_filter(function(r)
      return r < cur
    end, rows)
    -- no more blocks above: go to the start of the file
    target = before[#before - math.min(count, #before) + 1] or 0
  end

  go_to(target)
end

--- Home / End: to the start / end of the block containing the cursor. If you are already at that
--- edge, go up to the enclosing block (method → class); with no block, start/end of the file.
---@param to_start boolean
function M.edge(to_start)
  local blocks = get_blocks(vim.api.nvim_get_current_buf())
  if not blocks or #blocks == 0 then
    return vim.api.nvim_feedkeys(vim.keycode(to_start and "<Home>" or "<End>"), "n", false)
  end

  local cur = vim.api.nvim_win_get_cursor(0)[1] - 1
  local target -- the innermost wins: iterate in start order and keep the last one
  for _, b in ipairs(blocks) do
    if b.first <= cur and cur <= b.last then
      if to_start and b.first < cur then
        target = b.first
      elseif not to_start and b.last > cur then
        target = b.last
      end
    end
  end
  go_to(target or (to_start and 0 or vim.api.nvim_buf_line_count(0) - 1))
end

return M
