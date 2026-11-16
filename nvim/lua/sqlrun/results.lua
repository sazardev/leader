-- ── The result and information buffers ───────────────────────────────────────
-- One window per name (`sql://results`, `sql://info`), reused: the connection, the time and the rows as the client draws
-- them. `q` closes it, `r` runs the thing again (only the results buffer has one), `<C-y>` copies the whole buffer.
-- The flat style leaves the window alone: no numbers, no wrap, it is a block of text.
local M = {}

---@param text string
---@return string[]
function M.split(text)
  local lines = vim.split((text or ""):gsub("\r\n", "\n"), "\n", { plain = true })
  while #lines > 0 and lines[1] == "" do
    table.remove(lines, 1)
  end
  while #lines > 0 and lines[#lines] == "" do
    table.remove(lines)
  end
  return lines
end

---@param buf integer
local function copy(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local text = table.concat(lines, "\n")
  local ok = pcall(vim.fn.setreg, "+", text)
  if not ok then
    pcall(vim.fn.setreg, '"', text)
  end
  require("utils.log").info(ok and "SQL: copied to the clipboard" or 'SQL: copied (no system clipboard: in ")')
end

---@param opts { name: string, lines: string[], rerun: (fun())?, filetype: string? }
---@return integer buf
function M.show(opts)
  local buf = vim.fn.bufnr(opts.name)
  if buf == -1 then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, opts.name)
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].swapfile = false
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true, desc = "SQL close results" })
  end
  vim.bo[buf].modifiable = true
  vim.bo[buf].filetype = opts.filetype or ""
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.lines)
  vim.bo[buf].modifiable = false
  vim.keymap.set("n", "r", opts.rerun or "<Nop>", { buffer = buf, nowait = true, desc = "SQL run again" })
  vim.keymap.set("n", "<C-y>", function()
    copy(buf)
  end, { buffer = buf, nowait = true, desc = "SQL copy results" })
  if vim.fn.bufwinid(buf) == -1 then
    local from = vim.api.nvim_get_current_win()
    local height = require("core.settings").sql.results_height or 15
    vim.cmd(("botright %dsplit"):format(height))
    vim.api.nvim_win_set_buf(0, buf)
    vim.wo.wrap, vim.wo.number, vim.wo.relativenumber = false, false, false
    if vim.api.nvim_win_is_valid(from) then -- a picker that opened the run may be gone by now
      vim.api.nvim_set_current_win(from)
    end
  end
  return buf
end

return M
