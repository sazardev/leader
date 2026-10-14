-- ── Flat design: the selection chip ──────────────────────────────────────────
-- In the demo's list modals (harpoon) the chosen row is a solid blue chip as wide as its text plus a cell of air on
-- each side, not a bar across the window. `follow` keeps that chip on the cursor's row; every row gets the leading
-- cell so the text does not move when the chip passes over it.
local M = {}

local NS = vim.api.nvim_create_namespace "FlatChips"

---@param buf integer
---@param win integer
local function paint(buf, win)
  if not (vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win)) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  local cur = vim.api.nvim_win_get_cursor(win)[1] - 1
  for row, text in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local sel = row - 1 == cur and text ~= ""
    vim.api.nvim_buf_set_extmark(buf, NS, row - 1, 0, {
      virt_text = { { " ", sel and "FlatModalSel" or nil } },
      virt_text_pos = "inline",
      right_gravity = false,
    })
    if sel then
      vim.api.nvim_buf_set_extmark(buf, NS, row - 1, 0, { end_col = #text, hl_group = "FlatModalSel" })
      -- the trailing cell goes after the text
      vim.api.nvim_buf_set_extmark(buf, NS, row - 1, #text, {
        virt_text = { { " ", "FlatModalSel" } },
        virt_text_pos = "inline",
      })
    end
  end
end

--- Keep the chip on the cursor's row of `buf` (shown in `win`)
---@param buf integer
---@param win integer
function M.follow(buf, win)
  vim.wo[win].cursorline = false
  paint(buf, win)
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI" }, {
    buffer = buf,
    callback = function()
      paint(buf, win)
    end,
  })
end

return M
