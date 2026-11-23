-- ── Auto-import while typing Python (0 tokens) ────────────────────────────────
-- When an alias from the import catalog appears as a whole word in the line being
-- edited (`np.`, `pd.read_csv(...)`, `train_test_split(`…), its canonical import is
-- added at the top of the file right away. No menu to accept, no process started.
-- Strings and comments are skipped; ambiguous short names are opt-in (`auto = false`).
local imports = require "utils.pyimports"

local M = {}
local busy = false
local alias_cache = {}

--- A `#` outside of quoted strings on this side of the cursor.
---@param before string
---@return boolean
local function has_comment(before)
  local quote, i = nil, 1
  while i <= #before do
    local c = before:sub(i, i)
    if quote then
      if c == "\\" then
        i = i + 2
      else
        if c == quote then
          quote = nil
        end
        i = i + 1
      end
    else
      if c == '"' or c == "'" then
        quote = c
      elseif c == "#" then
        return true
      end
      i = i + 1
    end
  end
  return false
end

--- Treesitter knows about multiline docstrings; the line scanner only sees one line.
---@return boolean
local function inside_text_node()
  local ok, node = pcall(vim.treesitter.get_node)
  if not ok or not node then
    return false
  end
  while node do
    local kind = node:type()
    if kind:find("string", 1, true) or kind:find("comment", 1, true) then
      return true
    end
    node = node:parent()
  end
  return false
end

--- Statements to add for the line the cursor is on (pure over a buffer + cursor row).
---@param lines string[]
---@param row string the current line's text
---@param aliases table<string, string>? already-bound aliases (cached by the caller)
---@return string[]
function M.statements_for(lines, row, aliases)
  aliases = aliases or imports.aliases(lines)
  local present = {}
  for _, line in ipairs(lines) do
    present[vim.trim(line)] = true
  end
  local statements, seen = {}, {}
  for _, item in ipairs(imports.used_in_line(imports.mask(row))) do
    if not aliases[item.label] and not seen[item.line] and not present[item.line] then
      seen[item.line] = true
      statements[#statements + 1] = item.line
    end
  end
  return statements
end

--- Aliases of a buffer, reused while its changedtick does not move.
---@param buf integer
---@param lines string[]
---@return table<string, string>
local function aliases_for(buf, lines)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local hit = alias_cache[buf]
  if hit and hit.tick == tick then
    return hit.value
  end
  local value = imports.aliases(lines)
  alias_cache[buf] = { tick = tick, value = value }
  return value
end

--- Insert the imports for the current line, keeping the cursor on the text being typed.
---@param buf integer
---@return string[] what was inserted
function M.ensure(buf)
  local cfg = require("core.settings").python or {}
  local ic = cfg.imports or {}
  if ic.enabled == false or ic.auto_on_type == false or busy then
    return {}
  end
  busy = true
  local added = {}
  local ok, err = pcall(function()
    local line = vim.api.nvim_get_current_line()
    local before_col = vim.api.nvim_win_get_cursor(0)[2]
    local before = line:sub(1, before_col)
    if has_comment(before) or require("utils.pydata").string_context(before) or inside_text_node() then
      return
    end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local statements = M.statements_for(lines, line, aliases_for(buf, lines))
    if #statements == 0 then
      return
    end
    local at = imports.insert_row(lines)
    local view = vim.fn.winsaveview()
    added = imports.apply(buf, statements)
    if #added > 0 then
      -- The typing line moved down by as many rows as we inserted above it.
      if at + 1 <= view.lnum then
        view.lnum = view.lnum + #added
      end
      if at + 1 <= view.topline then
        view.topline = view.topline + #added
      end
      vim.fn.winrestview(view)
    end
  end)
  busy = false
  if not ok then
    require("utils.log").debug("pyauto: " .. tostring(err))
  end
  return added
end

return M
