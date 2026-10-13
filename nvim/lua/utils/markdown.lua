-- ── Markdown helpers (reading mode, spelling, checkboxes, word count) ───────
local log = require "utils.log"

local M = {}

local READING_WIDTH = 80
-- window options that reading mode changes (saved to restore them)
local READING_OPTS =
  { "wrap", "linebreak", "number", "relativenumber", "signcolumn", "cursorline", "colorcolumn", "statuscolumn" }

--- Left margin (in spaces) to center the text in `READING_WIDTH` columns
---@param win integer
---@return string
local function margin(win)
  return string.rep(" ", math.max(0, math.floor((vim.api.nvim_win_get_width(win) - READING_WIDTH) / 2)))
end

local function recenter()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.w[win].reading_saved then
      vim.wo[win].statuscolumn = margin(win)
    end
  end
end

--- Reading mode (toggle, this window only): text centered at 80 columns with
--- line wrapping, no numbers, signs or diagnostics; everything is restored on exit.
function M.reading_mode()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local saved = vim.w[win].reading_saved

  if saved then
    for _, name in ipairs(READING_OPTS) do
      vim.wo[win][name] = saved[name]
    end
    vim.diagnostic.enable(saved.diagnostics, { bufnr = buf })
    vim.w[win].reading_saved = nil
    return log.info "Reading mode: off"
  end

  saved = { diagnostics = vim.diagnostic.is_enabled { bufnr = buf } }
  for _, name in ipairs(READING_OPTS) do
    saved[name] = vim.wo[win][name]
  end
  vim.w[win].reading_saved = saved

  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].cursorline = false
  vim.wo[win].colorcolumn = ""
  vim.wo[win].statuscolumn = margin(win)
  vim.diagnostic.enable(false, { bufnr = buf })

  vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = vim.api.nvim_create_augroup("ReadingMode", { clear = true }),
    callback = recenter,
  })
  log.info "Reading mode: on"
end

--- Spell checker (es + en) in this buffer/window
function M.toggle_spell()
  local on = not vim.wo.spell
  vim.wo.spell = on
  if on then
    vim.bo.spelllang = "es,en"
  end
  log.info("Spell check: " .. (on and "on (es, en)" or "off"))
end

--- Words in the buffer (or selection) and reading time at ~200 wpm
function M.word_count()
  local wc = vim.fn.wordcount()
  local words = wc.visual_words or wc.words
  log.info(("%d words · ~%d min read"):format(words, math.max(1, math.ceil(words / 200))))
end

--- Check/uncheck the line's checkbox; if it isn't a task, turn it into one
--- (`- [ ] `), keeping the bullet (`-*+` or `1.`) and indentation.
function M.toggle_checkbox()
  local line = vim.api.nvim_get_current_line()

  for _, bullet in ipairs { "[-*+]", "%d+[.)]" } do
    local indent, b, mark, rest = line:match("^(%s*)(" .. bullet .. ")%s+%[([ xX])%]%s*(.*)$")
    if indent then
      return vim.api.nvim_set_current_line(("%s%s [%s] %s"):format(indent, b, mark == " " and "x" or " ", rest))
    end
    indent, b, rest = line:match("^(%s*)(" .. bullet .. ")%s+(.*)$")
    if indent then
      return vim.api.nvim_set_current_line(("%s%s [ ] %s"):format(indent, b, rest))
    end
  end

  local indent, rest = line:match "^(%s*)(.*)$"
  vim.api.nvim_set_current_line(indent .. "- [ ] " .. rest)
end

return M
