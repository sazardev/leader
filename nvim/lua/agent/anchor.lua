-- ── Target anchor ────────────────────────────────────────────────────────────
-- An extmark covering the target's lines: if you edit above it while the agent
-- works, the range shifts by itself. When applying a result it is also checked
-- that the text is still what was sent (if not, it is discarded instead of overwritten).
local M = {}

local NS = vim.api.nvim_create_namespace "agent.anchor"

--- End of the range as an extmark position: ALWAYS (last line, end of that line).
--- The "(next line, col 0)" form would fail for a target ending on the last
--- line of the buffer: nvim clamps that end and the range would collapse to one row.
---@param buf integer
---@param last integer 1-based, inclusive
---@return integer end_row, integer end_col
function M.finish(buf, last)
  local line = vim.api.nvim_buf_get_lines(buf, last - 1, last, false)[1] or ""
  return last - 1, #line
end

--- End for PAINTING a range: (next line, col 0) includes the line break, so
--- `hl_eol` also covers the last row; only on the last line of the buffer is there no "next"
--- and it falls back to (last, end). Visual only: the logic uses `finish`.
---@param buf integer
---@param last integer 1-based, inclusive
---@return integer end_row, integer end_col
function M.highlight_end(buf, last)
  if last < vim.api.nvim_buf_line_count(buf) then
    return last, 0
  end
  return M.finish(buf, last)
end

---@param buf integer
---@param first integer 1-based
---@param last integer 1-based, inclusive
---@return integer id
function M.create(buf, first, last)
  local end_row, end_col = M.finish(buf, last)
  return vim.api.nvim_buf_set_extmark(buf, NS, first - 1, 0, {
    end_row = end_row,
    end_col = end_col,
    right_gravity = false,
    end_right_gravity = false,
    invalidate = true,
    strict = false,
  })
end

--- Current range (1-based, inclusive); nil if the anchor's text was deleted
---@param buf integer
---@param id integer
---@return integer?, integer?
function M.range(buf, id)
  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end
  local mark = vim.api.nvim_buf_get_extmark_by_id(buf, NS, id, { details = true })
  local details = mark[3]
  if not details or details.invalid then
    return nil
  end
  return mark[1] + 1, details.end_row + 1
end

--- Is the text under the anchor still what was sent?
---@param job table
---@return boolean
function M.unchanged(job)
  local first, last = M.range(job.buf, job.anchor)
  if not first then
    return false
  end
  return vim.deep_equal(vim.api.nvim_buf_get_lines(job.buf, first - 1, last, false), job.target.lines)
end

---@param buf integer
---@param id integer
function M.delete(buf, id)
  if vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_del_extmark, buf, NS, id)
  end
end

return M
