-- ── Does the new code even parse? ────────────────────────────────────────────
-- The cheapest checker there is, for every language that has a treesitter parser, with no server running: parse the file
-- as it would be AFTER the replacement and compare the syntax errors with the file as it is. A candidate that adds errors
-- is broken, whatever it means; one that adds none may still be wrong, which is what the LSP check after accepting is for.
local M = {}

---@param text string
---@param lang string
---@return integer count, integer? first_row 0-based row of the first error
function M.errors(text, lang)
  local ok, parser = pcall(vim.treesitter.get_string_parser, text, lang)
  if not ok or not parser then
    return 0
  end
  local parsed = parser:parse()
  local root = parsed and parsed[1] and parsed[1]:root()
  if not root or not root:has_error() then
    return 0
  end
  local count, first = 0, nil
  local function walk(node)
    if node:type() == "ERROR" or node:missing() then
      count = count + 1
      first = first or node:start()
    end
    if node:has_error() then
      for child in node:iter_children() do
        walk(child)
      end
    end
  end
  walk(root)
  return count, first
end

---@param ft string
---@return string? lang its parser, nil when there is none installed
function M.lang(ft)
  local lang = vim.treesitter.language.get_lang(ft) or ft
  return vim.treesitter.language.add(lang) and lang or nil
end

--- Would replacing lines [first, last] of `lines` with `new` add syntax errors? Returns nil when it cannot tell (no parser)
---@param lines string[] the whole file
---@param first integer 1-based
---@param last integer
---@param new string[]
---@param ft string
---@return { added: integer, row: integer? }?
function M.after_replace(lines, first, last, new, ft)
  local lang = M.lang(ft)
  if not lang then
    return nil
  end
  local before = M.errors(table.concat(lines, "\n"), lang)
  local candidate = vim.list_extend(vim.list_slice(lines, 1, first - 1), new)
  vim.list_extend(candidate, vim.list_slice(lines, last + 1))
  local after, row = M.errors(table.concat(candidate, "\n"), lang)
  return { added = math.max(0, after - before), row = row and (row + 1) or nil }
end

return M
