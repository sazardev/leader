-- ── Go sentinel errors: live ghost text ───────────────────────────────────────
-- When you type an error's NAME, the rest of the declaration shows up by itself,
-- in grey to the right of the cursor, and grows with each letter:
--   ErrDescriptionTooLong|   →   ErrDescriptionTooLong = errors.New("description too long")
-- Tab accepts it (cursor at end of line); Enter accepts it and opens a new line.
-- Keep typing and the suggestion adjusts; Esc dismisses it.
--   inside `var ( … )`      ErrNotFound
--   after `var `            var ErrNotFound
--   at package level        ErrNotFound      (`var ` is prepended)
-- It also accepts the unexported name (`errNotFound`).
local M = {}

local NS = vim.api.nvim_create_namespace "goerrors"
local SCAN_LINES = 300 -- how far up to look for the `var (`

--- "NotFound" → "not found", "InvalidID" → "invalid id", "HTTPError" → "http error"
---@param name string # with or without the `Err` prefix
---@return string
function M.message(name)
  local rest = name:gsub("^[eE]rr", "")
  rest = rest:gsub("_", " "):gsub("(%l)(%u)", "%1 %2"):gsub("(%u+)(%u%l)", "%1 %2"):gsub("(%d)(%a)", "%1 %2")
  return (rest:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""):lower())
end

--- Does line `row` fall inside a package-level `var ( … )`?
--- It looks at the text, not treesitter: the line being typed (a bare `ErrX`)
--- doesn't parse and leaves the tree broken exactly where it's needed.
---@param row integer 1-indexed
---@return boolean
local function in_var_block(row)
  local first = math.max(row - 1 - SCAN_LINES, 0)
  local lines = vim.api.nvim_buf_get_lines(0, first, row - 1, false)
  for i = #lines, 1, -1 do
    local line = lines[i]
    if line:match "^var%s*%(%s*$" or line:match "^var%s*%(%s*//" then
      return true
    elseif line:match "^%)" or line:match "^%a" then
      return false -- closed the block, or it is another declaration at column 0
    end
  end
  return false
end

---@class GoErrorContext
---@field name string # the typed name (`ErrNotFound`)
---@field start integer # column (0-indexed) where the name starts
---@field prefix string # text that goes BEFORE the name on accept (`var ` or nothing)
---@field suffix string # text that goes AFTER (` = errors.New("not found")`)

--- Is an error being declared by its name, with the cursor at the end of the line? (nil = no)
---@param line string
---@param row integer 1-indexed
---@param col integer 0-indexed
---@return GoErrorContext?
function M.context(line, row, col)
  if line:sub(col + 1):find "%S" then
    return nil
  end
  local before = line:sub(1, col)
  local function build(name, start, prefix)
    return { name = name, start = start, prefix = prefix, suffix = (' = errors.New("%s")'):format(M.message(name)) }
  end
  local name = before:match "^var%s+([eE]rr%u[%w_]*)$"
  if name then
    return build(name, col - #name, "")
  end
  local indent
  indent, name = before:match "^(%s*)([eE]rr%u[%w_]*)$"
  if not name then
    return nil
  end
  if in_var_block(row) then
    return build(name, #indent, "")
  elseif indent == "" then
    return build(name, 0, "var ")
  end
end

---@return GoErrorContext?, integer?, integer? # context, row (1-indexed), column
local function current()
  if vim.bo.filetype ~= "go" or vim.api.nvim_get_mode().mode ~= "i" then
    return nil
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  return M.context(vim.api.nvim_get_current_line(), row, col), row, col
end

--- Is there a suggestion in view? (blink uses it to hide its menu)
---@return boolean
function M.active()
  return current() ~= nil
end

local function clear(buf)
  vim.api.nvim_buf_clear_namespace(buf or 0, NS, 0, -1)
end

local function render()
  local buf = vim.api.nvim_get_current_buf()
  clear(buf)
  local err, row, col = current()
  if not err then
    return
  end
  local ghost = { { err.suffix, "Comment" } }
  vim.api.nvim_buf_set_extmark(buf, NS, row - 1, col, { virt_text = ghost, virt_text_pos = "inline", hl_mode = "combine" })
  if err.prefix ~= "" then
    local pre = { { err.prefix, "Comment" } }
    vim.api.nvim_buf_set_extmark(buf, NS, row - 1, err.start, { virt_text = pre, virt_text_pos = "inline", hl_mode = "combine" })
  end
end

--- Write the suggestion. Returns false if there was none (so the key goes on its way).
--- Blink calls this from an `expr` mapping (with the text locked), so the edit is scheduled.
---@param newline? boolean # also opens a new line (Enter)
---@return boolean
function M.accept(newline)
  local err, row = current()
  if not err then
    return false
  end
  vim.schedule(function()
    clear()
    local line = vim.api.nvim_get_current_line()
    -- suffix first (on the right), then the prefix: that way the columns don't shift
    vim.api.nvim_buf_set_text(0, row - 1, #line, row - 1, #line, { err.suffix })
    if err.prefix ~= "" then
      vim.api.nvim_buf_set_text(0, row - 1, err.start, row - 1, err.start, { err.prefix })
    end
    vim.api.nvim_win_set_cursor(0, { row, #vim.api.nvim_get_current_line() })
    if newline then
      vim.api.nvim_feedkeys(vim.keycode "<CR>", "n", false)
    end
  end)
  return true
end

--- Draw the suggestion while typing. Call once at startup.
function M.setup()
  local group = vim.api.nvim_create_augroup("GoErrors", { clear = true })
  vim.api.nvim_create_autocmd({ "InsertEnter", "TextChangedI", "TextChangedP", "CursorMovedI" }, {
    group = group,
    pattern = "*.go",
    callback = render,
  })
  vim.api.nvim_create_autocmd({ "InsertLeave", "BufLeave" }, {
    group = group,
    pattern = "*.go",
    callback = function(args)
      clear(args.buf)
    end,
  })
end

return M
