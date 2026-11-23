-- ── Python REPL: presentación ligera ──────────────────────────────────────────
-- Un float para la salida segmentada y las respuestas del modelo local. No toma
-- el foco del código más de lo necesario y se cierra con q / Esc.
local M = {}

---@param title string
---@param text string
---@param filetype string?
---@return integer? win
function M.float(title, text, filetype)
  local lines = vim.split(text or "", "\n", { plain = true })
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = filetype or "markdown"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false

  local width = math.min(96, math.max(40, vim.o.columns - 10))
  local height = math.min(math.max(6, vim.o.lines - 6), math.max(6, #lines + 2))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = require("ui.flat").border(),
    title = " " .. title .. " ",
    title_pos = "left",
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].winhighlight =
    "NormalFloat:NormalFloat,FloatBorder:FloatBorder,FloatTitle:FloatTitle,EndOfBuffer:NormalFloat"
  for _, key in ipairs { "q", "<Esc>" } do
    vim.keymap.set("n", key, function()
      pcall(vim.api.nvim_win_close, win, true)
    end, { buffer = buf, nowait = true, desc = "Python REPL close" })
  end
  return win
end

return M
