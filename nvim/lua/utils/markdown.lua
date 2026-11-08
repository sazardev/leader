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

--- Is this buffer open in a reading window?
---@param buf integer?
---@return boolean
local function has_reading_window(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf or 0)) do
    if vim.w[win].reading_saved then
      return true
    end
  end
  return false
end

--- Reading mode (toggle, this window only): text centered at 80 columns with
--- line wrapping, no numbers, signs or diagnostics, locked (`modifiable=false`):
--- clicks and edits do nothing until <Esc> (utils/escape.lua) leaves it. Everything is restored on exit.
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
    if not has_reading_window(buf) then
      vim.bo[buf].modifiable = saved.modifiable
      vim.b[buf].reading_locked = nil
    end
    return log.info "Reading mode: off (editable)"
  end

  saved = { diagnostics = vim.diagnostic.is_enabled { bufnr = buf }, modifiable = vim.bo[buf].modifiable }
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
  vim.b[buf].reading_locked = true
  vim.bo[buf].modifiable = false

  vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = vim.api.nvim_create_augroup("ReadingMode", { clear = true }),
    callback = recenter,
  })
  log.info "Reading mode: on (Esc to edit)"
end

--- Is the current window (or the window of `buf`) in reading mode?
---@param buf integer?
---@return boolean
function M.is_reading(buf)
  if buf then
    return has_reading_window(buf) or vim.b[buf].reading_locked == true
  end
  local win = vim.api.nvim_get_current_win()
  return vim.w[win].reading_saved ~= nil
end

--- Auto reading mode for *.md and *.mdx (both filetype `markdown` after ftdetect/mdx.lua):
--- opening one enters the locked reading mode above; <Esc> (utils/escape.lua) leaves it.
function M.setup()
  local group = vim.api.nvim_create_augroup("MarkdownReading", { clear = true })
  local function enter(buf)
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    if vim.bo[buf].filetype ~= "markdown" or vim.bo[buf].buftype ~= "" then
      return
    end
    -- first open: style the current window (reading_mode locks the buffer)
    if not has_reading_window(buf) and vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win()) == buf then
      M.reading_mode()
      return
    end
    -- split of a reading buffer: style the fresh window too
    if vim.b[buf].reading_locked then
      for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        if not vim.w[win].reading_saved then
          local cur = vim.api.nvim_get_current_win()
          vim.api.nvim_set_current_win(win)
          M.reading_mode()
          vim.api.nvim_set_current_win(cur)
        end
      end
    end
  end
  -- FileType fires on open; WinEnter/BufEnter style a split of a reading buffer
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "markdown",
    callback = function(ev)
      vim.schedule(function()
        enter(ev.buf)
      end)
    end,
  })
  vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
    group = group,
    callback = function(ev)
      vim.schedule(function()
        enter(ev.buf)
      end)
    end,
  })
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
  if not vim.bo.modifiable then
    return log.info "Reading mode: Esc to edit"
  end
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
