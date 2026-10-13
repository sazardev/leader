-- ── Reading panel (markdown, centered) ───────────────────────────────────────
-- For what is read calmly: a run's detail or the spend report. q/Esc close.
require("agent.ui.highlights").ensure()

local M = {}

---@param lines string[]
---@param title string
function M.open(lines, title)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  vim.diagnostic.enable(false, { bufnr = buf }) -- the markdown linter has nothing to say about a read-only panel
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local width = math.min(vim.o.columns - 6, 110)
  local height = math.min(vim.o.lines - 6, math.max(#lines + 2, 12))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "single",
    title = (" %s · Y copy all · q close "):format(title),
    title_pos = "left",
  })
  local wo = vim.wo[win]
  wo.wrap = true
  wo.linebreak = true
  wo.winhighlight = "NormalFloat:AgentFloat,FloatBorder:AgentBorder,FloatTitle:AgentTitle"

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.keymap.set("n", "Y", function()
    require("agent.ui.clipboard").copy(table.concat(lines, "\n") .. "\n", "the whole panel")
  end, { buffer = buf, nowait = true, desc = "Agent copy panel" })
  for _, key in ipairs { "q", "<Esc>" } do
    vim.keymap.set("n", key, close, { buffer = buf, nowait = true, desc = "Agent close panel" })
  end
end

return M
