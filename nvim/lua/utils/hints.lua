-- ── Key hints that fit ───────────────────────────────────────────────────────
-- A line of hints ("Space stage · a all · q cancel") that never outgrows its window: Neovim cuts a title or footer
-- that is too wide from its START, which turns `Ctrl-g AI` into `<g AI`. So the hints that matter least are dropped first.
local M = {}

--- Joins the parts with " · " dropping the lowest-priority ones (higher number; the last of them when equal) until the
--- line fits `width` columns
---@param parts { [1]: string, [2]: integer }[]  text and priority (1 = essential)
---@param width integer
---@return string
function M.fit(parts, width)
  parts = vim.list_slice(parts)
  local function joined()
    return table.concat(
      vim.tbl_map(function(p)
        return p[1]
      end, parts),
      " · "
    )
  end
  while vim.fn.strdisplaywidth(joined()) > width and #parts > 1 do
    local worst = 1
    for i, p in ipairs(parts) do
      if p[2] >= parts[worst][2] then
        worst = i
      end
    end
    table.remove(parts, worst)
  end
  return joined()
end

return M
