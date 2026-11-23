-- ── Results under the statement (extmarks) ────────────────────────────────────
-- After a run, a small `✓ 5 rows · 75 ms` at the end of the statement's last line. No window, no buffer: the editor
-- keeps its flow. One mark per buffer, replaced by the next run. `rows`/`label` are pure (test-langs.lua).
local M = {}

local NS = vim.api.nvim_create_namespace "sqlrun_inline"

--- Counts data rows in what a client printed (sqlite3's box, psql's table, a plain list).
---@param output string?
---@return integer
function M.rows(output)
  local lines = require("sqlrun.results").split(output or "")
  local boxed = 0
  for _, line in ipairs(lines) do
    if line:match "^[%│|║]" then
      boxed = boxed + 1
    end
  end
  if boxed > 0 then
    return math.max(boxed - 1, 0) -- the first boxed line is the header
  end
  local count = 0
  for _, line in ipairs(lines) do
    if not line:match("^%s*[-+]+%s*$") and not line:match("^%s*%(%d+ row") then
      count = count + 1
    end
  end
  return math.max(count - 1, 0)
end

---@param rows integer
---@param ms integer
---@param ok boolean
---@return string
function M.label(rows, ms, ok)
  if not ok then
    return (" ✗ failed · %d ms"):format(ms)
  end
  return (" ✓ %d %s · %d ms"):format(rows, rows == 1 and "row" or "rows", ms)
end

---@param buf integer
---@param last integer 1-based line of the statement's end
---@param text string
---@param group string?
function M.show(buf, last, text, group)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  local count = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_extmark(buf, NS, math.max(math.min(last, count) - 1, 0), 0, {
    virt_text = { { text, group or "SqlStatus" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
  })
end

---@param buf integer
function M.clear(buf)
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  end
end

return M
