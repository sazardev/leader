-- ── Reading panel (markdown, centered) ───────────────────────────────────────
-- For what is read calmly: a run's detail or the spend report. q/Esc close; with `on_back`, BS goes back to where it
-- was opened from (the run history).
require("agent.ui.highlights").ensure()

local M = {}

---@param lines string[]
---@param title string
---@param opts? { on_back?: fun(), hint?: string, on_open?: fun(buf: integer, win: integer, close: fun()) }
---  hint: replaces "Y copy all · q close" in the title; on_open: bind more keys (the plan panel toggles steps with them)
function M.open(lines, title, opts)
  opts = opts or {}
  -- the "checking…" note that announced this report would sit over it
  pcall(function()
    require("ui.flat.notify").close_progress()
  end)
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
    border = require("ui.flat").border(),
    title = opts.hint and (" %s · %s "):format(title, opts.hint)
      or (" %s · Y copy all ·%s q close "):format(title, opts.on_back and " BS back ·" or ""),
    title_pos = "left",
  })
  local wo = vim.wo[win]
  wo.wrap = true
  wo.linebreak = true
  wo.winhighlight =
    "NormalFloat:AgentFloat,FloatBorder:AgentBorder,FloatTitle:AgentTitle,EndOfBuffer:AgentFloat,SignColumn:AgentFloat"

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
  if opts.on_open then
    opts.on_open(buf, win, close)
  end
  if opts.on_back then
    vim.keymap.set("n", "<BS>", function()
      close()
      opts.on_back()
    end, { buffer = buf, nowait = true, desc = "Agent back to the list" })
  end
end

return M
