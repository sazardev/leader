-- ── Project kit: a page to write on ──────────────────────────────────────────
-- A flat floating Markdown buffer for the free text the model turns into a document (the spec, a design or a stack
-- described in your words). `:w` or Ctrl-s sends it, `q` closes it. What was written is kept per document for the session,
-- so closing by mistake or a failed request loses nothing: the next open brings it back.
require("agent.ui.highlights").ensure()

local M = {}

local NS = vim.api.nvim_create_namespace "AgentKitDraft"

---@type table<string, string[]>
local kept = {}

---@param id string
---@return string?
function M.kept(id)
  return kept[id] and table.concat(kept[id], "\n") or nil
end

---@param id string
function M.forget(id)
  kept[id] = nil
end

---@param buf integer
---@return string
local function text_of(buf)
  return vim.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
end

---@class KitDraftOpts
---@field id string            which document (what is kept between opens)
---@field title string
---@field hint string[]        guidance shown above the text (not part of it)
---@field text string?         what to start from when nothing is kept (the current SPEC.md…)

--- Opens the page; `on_submit(text)` gets what was written (never empty)
---@param opts KitDraftOpts
---@param on_submit fun(text: string)
function M.open(opts, on_submit)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_name(buf, ("kit://%s-%d"):format(opts.id, buf))
  local start = kept[opts.id] or (opts.text and vim.split(opts.text, "\n", { plain = true })) or { "" }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, start)
  vim.bo[buf].modified = false

  local width = math.min(100, vim.o.columns - 8)
  local height = math.max(12, math.min(vim.o.lines - 8, math.floor(vim.o.lines * 0.7)))
  local flat = require "ui.flat"
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = flat.border(),
    title = { { opts.title:upper() .. " ", "FlatModalTitle" } },
    title_pos = "left",
    footer = { { " :w / Ctrl-s send · q close (kept) ", require("utils.modal").hl.muted } },
    footer_pos = "right",
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].conceallevel = 0
  if flat.enabled() then
    vim.wo[win].winhighlight = "EndOfBuffer:NormalFloat"
    require("ui.flat.motion").enter { win }
  end
  vim.bo[buf].filetype = "markdown"
  vim.b[buf].completion = false -- free text: no completion popup over what you write
  vim.api.nvim_buf_set_extmark(buf, NS, 0, 0, {
    virt_lines = vim.list_extend(
      vim.tbl_map(function(line)
        return { { line, require("utils.modal").hl.muted } }
      end, opts.hint),
      { { { "" } } }
    ),
    virt_lines_above = true,
  })
  vim.fn.winrestview { topfill = #opts.hint + 1 } -- the hint above line 1 is on screen, not scrolled away

  local function keep()
    if vim.api.nvim_buf_is_valid(buf) then
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      kept[opts.id] = text_of(buf) ~= "" and lines or nil
    end
  end
  local function close()
    keep()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  local function submit()
    local text = text_of(buf)
    if text == "" then
      return require("utils.log").info "Setup: write something first (q closes)"
    end
    vim.cmd "stopinsert"
    close()
    on_submit(text)
  end

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      vim.bo[buf].modified = false
      submit()
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", { buffer = buf, callback = keep })
  vim.keymap.set({ "n", "i" }, "<C-s>", submit, { buffer = buf, nowait = true, desc = "Setup send draft" })
  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true, desc = "Setup close draft" })
  if #start == 1 and start[1] == "" then
    vim.cmd "startinsert"
  end
end

return M
