-- ── Code folds by leader (<leader>z menu) ────────────────────────────────────
-- Folds a function, a type or an object literal by what the code IS (treesitter), not by indentation:
-- the one under the cursor, the methods of the type you are in, or every one of them in the file. The
-- folds themselves come from nvim-ufo (plugins/editing/ufo.lua); this only closes the right ones.
-- Functions and types use the `textobjects` queries (the same definition as `af`/`ac`, see
-- agent/context/scopes.lua); objects are found by node type because no query defines them.
local scopes = require "agent.context.scopes"

local M = {}

-- Object-like literals by EXACT node type (a substring match would catch argument lists and types)
local OBJECT = {
  object = true, -- JS/TS/JSON
  array = true, -- JS/TS/JSON
  table_constructor = true, -- Lua
  composite_literal = true, -- Go
  dictionary = true, -- Python
  list = true, -- Python
  set = true, -- Python
  struct_expression = true, -- Rust
  array_expression = true, -- Rust
  array_initializer = true, -- Java/C#
  initializer_expression = true, -- C#
  list_literal = true, -- Dart
  set_or_map_literal = true, -- Dart
  hash = true, -- Ruby
  block_mapping = true, -- YAML
  block_sequence = true, -- YAML
  flow_mapping = true, -- YAML
  flow_sequence = true, -- YAML
}

local CAPTURE = { ["function"] = "function.outer", type = "class.outer" }
local LABEL = { ["function"] = "function", type = "type", object = "object" }

---@alias FoldKind "function"|"type"|"object"

---@class FoldRange
---@field first integer row (0-based) where it starts
---@field last integer row (0-based, inclusive) where it ends

---@param msg string
local function say(msg)
  vim.notify(msg, vim.log.levels.INFO)
end

---@param node TSNode
---@return integer, integer
local function rows(node)
  local sr, _, er, ec = node:range()
  -- an end at column 0 includes the line break: the node ends on the previous row
  if ec == 0 and er > sr then
    er = er - 1
  end
  return sr, er
end

---@param node TSNode
---@param fn fun(node: TSNode)
local function walk(node, fn)
  local sr, _, er = node:range()
  if er == sr then
    return -- one row: nothing inside it can be folded
  end
  fn(node)
  for child in node:iter_children() do
    walk(child, fn)
  end
end

--- Multi-line ranges of `kind` in the buffer, or nil if there is no parser (or no textobjects query)
---@param buf integer
---@param kind FoldKind
---@return FoldRange[]?
local function collect(buf, kind)
  local root, _, query = scopes.parse(buf)
  if not root or (kind ~= "object" and not query) then
    return nil
  end
  local found, seen = {}, {}
  local function add(node)
    local first, last = rows(node)
    local key = first .. ":" .. last
    if last > first and not seen[key] then
      seen[key] = true
      found[#found + 1] = { first = first, last = last }
    end
  end
  if kind == "object" then
    walk(root, function(node)
      if OBJECT[node:type()] then
        add(node)
      end
    end)
  else
    for id, node in query:iter_captures(root, buf, 0, -1) do
      if query.captures[id] == CAPTURE[kind] then
        add(node)
      end
    end
  end
  return found
end

--- Is the range hidden or folded right now (its own fold, or an outer one that is closed)?
---@param r FoldRange
---@return boolean
local function is_closed(r)
  return vim.fn.foldclosed(r.first + 1) ~= -1
end

--- Close the fold that IS this range. If the line has no fold of its own (one-liner, or ufo has not
--- made one yet) `:foldclose` would hit the PARENT fold: that is undone and a manual fold is made instead.
---@param r FoldRange
local function close(r)
  local first, last = r.first + 1, r.last + 1
  vim.wo.foldenable = true
  pcall(vim.cmd, first .. "foldclose")
  local start = vim.fn.foldclosed(first)
  if start == first and vim.fn.foldclosedend(first) <= last then
    return
  end
  if start ~= -1 then
    pcall(vim.cmd, start .. "foldopen")
  end
  pcall(vim.cmd, ("%d,%dfold"):format(first, last))
end

---@param kind FoldKind
---@return FoldRange[]?
local function current(kind)
  local list = collect(vim.api.nvim_get_current_buf(), kind)
  if not list then
    say "No syntax tree in this buffer: nothing to fold by structure"
  end
  return list
end

--- Ranges that contain the row, innermost first
---@param list FoldRange[]
---@param row integer
---@return FoldRange[]
local function around(list, row)
  local result = vim.tbl_filter(function(r)
    return r.first <= row and row <= r.last
  end, list)
  table.sort(result, function(a, b)
    return a.last - a.first < b.last - b.first
  end)
  return result
end

--- Close ranges inner-first (a later start is nested inside an earlier one)
---@param list FoldRange[]
---@return integer how many were closed
local function close_all(list)
  table.sort(list, function(a, b)
    return a.first > b.first
  end)
  local n = 0
  for _, r in ipairs(list) do
    if not is_closed(r) then
      close(r)
      n = n + 1
    end
  end
  return n
end

--- Fold the `kind` under the cursor. If it is already folded, the next one out (a closure → its
--- function, a method → its class is folded with `type`): pressing again walks outwards.
---@param kind FoldKind
function M.here(kind)
  local list = current(kind)
  if not list then
    return
  end
  local candidates = around(list, vim.api.nvim_win_get_cursor(0)[1] - 1)
  for _, r in ipairs(candidates) do
    if not is_closed(r) then
      return close(r)
    end
  end
  say(#candidates > 0 and ("This %s is already folded"):format(LABEL[kind]) or ("No %s under the cursor"):format(LABEL[kind]))
end

--- Fold every `kind` in the file
---@param kind FoldKind
function M.all(kind)
  local list = current(kind)
  if not list then
    return
  end
  local n = close_all(list)
  say(n > 0 and ("Folded %d %s%s"):format(n, LABEL[kind], n == 1 and "" or "s") or ("No %ss to fold"):format(LABEL[kind]))
end

--- Fold the methods (every function) of the type the cursor is in, leaving the type itself open
function M.methods()
  local types = current "type"
  local fns = types and current "function"
  if not (types and fns) then
    return
  end
  local owner = around(types, vim.api.nvim_win_get_cursor(0)[1] - 1)[1]
  if not owner then
    return say "No type under the cursor"
  end
  local inside = vim.tbl_filter(function(f)
    return f.first > owner.first and f.last <= owner.last
  end, fns)
  local n = close_all(inside)
  say(n > 0 and ("Folded %d method%s"):format(n, n == 1 and "" or "s") or "No methods to fold in this type")
end

--- Fold the innermost open fold around the cursor (`zc`); again, and it closes the one around that
function M.block()
  if vim.fn.foldlevel(vim.api.nvim_win_get_cursor(0)[1]) == 0 then
    return say "No block to fold here"
  end
  vim.wo.foldenable = true
  pcall(vim.cmd, "normal! zc")
end

--- nvim-ufo, loaded on demand (it is lazy: a global menu can be used before any file opened it)
---@return table?
local function ufo()
  local ok, mod = pcall(require, "ufo")
  if not ok then
    say "nvim-ufo is not available"
  end
  return ok and mod or nil
end

--- Fold everything: only the outline is left
function M.close_all_folds()
  local u = ufo()
  if u then
    u.closeAllFolds()
  end
end

--- Unfold everything
function M.open_all_folds()
  local u = ufo()
  if u then
    u.openAllFolds()
  end
end

--- Fold everything nested deeper than `level` (1 = top-level folds stay open)
---@param level integer
function M.level(level)
  local u = ufo()
  if u then
    u.closeFoldsWith(level)
  end
end

--- Fold everything except what contains the cursor
function M.focus()
  local u = ufo()
  if u then
    u.closeAllFolds()
    pcall(vim.cmd, "normal! zv")
  end
end

--- Unfold the fold under the cursor and everything nested in it
function M.open_here()
  pcall(vim.cmd, "normal! zO")
end

--- Toggle the fold under the cursor
function M.toggle()
  pcall(vim.cmd, "normal! za")
end

return M
