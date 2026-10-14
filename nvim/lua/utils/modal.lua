-- ── Floating modals ─────────────────────────────────────────────────────────
-- Same flat style as the rest of the UI (ui/flat): a filled block, centered, with a small faint title.
-- Colors: theme groups (base46), so they change with the active theme.
--
-- Each line is a string, or a list of { text, hl } segments to paint
-- different parts of the same line (e.g. folder in one color, mark in another).
--
-- M.input   → text + editable field (Enter confirms, Esc cancels)
-- M.confirm → text + [y] / [n] (only y confirms, any other key cancels)
local M = {}

-- Modal groups → theme groups (see base46/integrations/nvimtree.lua)
local GROUPS = {
  NvModalFolder = { link = "NvimTreeFolderName" },
  NvModalFile = { link = "Normal" },
  NvModalTree = { link = "NvimTreeIndentMarker" },
  NvModalMark = { link = "NvimTreeSpecialFile" },
  NvModalWarn = { link = "DiagnosticWarn" },
  NvModalKey = { link = "Special" },
  NvModalMuted = { link = "Comment" },
}
for name, def in pairs(GROUPS) do
  vim.api.nvim_set_hl(0, name, { link = def.link, default = true })
end
M.hl = {
  folder = "NvModalFolder",
  file = "NvModalFile",
  tree = "NvModalTree",
  mark = "NvModalMark",
  warn = "NvModalWarn",
  key = "NvModalKey",
  muted = "NvModalMuted",
}

local NS = vim.api.nvim_create_namespace "NvModal"

---@param line string|table[]
---@return string
local function plain(line)
  if type(line) == "string" then
    return line
  end
  local parts = {}
  for _, seg in ipairs(line) do
    parts[#parts + 1] = seg[1]
  end
  return table.concat(parts)
end

---@param lines string[]
---@return integer
local function width_of(lines)
  local w = 0
  for _, l in ipairs(lines) do
    w = math.max(w, vim.fn.strdisplaywidth(plain(l)))
  end
  return math.min(math.max(w + 4, 44), vim.o.columns - 4)
end

---@param buf integer
---@param lines (string|table[])[]
local function paint(buf, lines)
  for i, line in ipairs(lines) do
    if type(line) == "table" then
      local col = 0
      for _, seg in ipairs(line) do
        local text, hl = seg[1], seg[2]
        if hl then
          vim.api.nvim_buf_set_extmark(buf, NS, i - 1, col, { end_col = col + #text, hl_group = hl })
        end
        col = col + #text
      end
    end
  end
end

---@param lines (string|table[])[]
---@param opts { title?: string, editable?: boolean }
---@return integer buf, integer win, function close
local function open(lines, opts)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local text = vim.tbl_map(plain, lines)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, text)
  paint(buf, lines)
  vim.bo[buf].modifiable = opts.editable or false

  local width = width_of(lines)
  local height = #lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = require("ui.flat").border(),
    title = opts.title and (" %s "):format(opts.title:upper()) or nil,
    title_pos = "left",
  })

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true, desc = "Close" })
  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true, desc = "Close" })
  return buf, win, close
end

---@param lines (string|table[])[]
---@param opts { title?: string }
---@param on_submit fun(text: string)
function M.input(lines, opts, on_submit)
  local prompt = "> "
  vim.list_extend(lines, { "", { { prompt, M.hl.key } } })
  local last = #lines
  vim.list_extend(lines, { { { "Enter confirm · Esc cancel", M.hl.muted } } }) -- the key hints, faint, under the field
  local buf, win, close = open(lines, { title = opts.title, editable = true })

  vim.api.nvim_win_set_cursor(win, { last, #prompt })
  vim.api.nvim_buf_set_extmark(buf, NS, last - 1, 0, { line_hl_group = "FlatInput" }) -- the field: one step darker than the block
  vim.b[buf].completion = false -- blink must not suggest anything in a free-text field
  vim.cmd "startinsert!"

  -- On close we must leave insert: `startinsert!` would leave insert mode active in the code
  -- window we return to, and whatever you type next would be written into your file.
  local function leave()
    close()
    vim.cmd "stopinsert"
  end

  local function submit()
    local text = vim.api.nvim_buf_get_lines(buf, last - 1, last, false)[1]:sub(#prompt + 1)
    leave()
    on_submit(vim.trim(text))
  end
  vim.keymap.set({ "i", "n" }, "<CR>", submit, { buffer = buf, nowait = true, desc = "Submit" })
  vim.keymap.set("i", "<Esc>", leave, { buffer = buf, nowait = true, desc = "Close" })
end

---@param lines (string|table[])[]
---@param opts { title?: string }
---@param on_yes fun()
function M.confirm(lines, opts, on_yes)
  vim.list_extend(lines, {
    "",
    { { "[y]", M.hl.key }, { " yes    " }, { "[n / q / <Esc>]", M.hl.key }, { " no", M.hl.muted } },
  })
  local buf, _, close = open(lines, { title = opts.title })

  vim.keymap.set("n", "n", close, { buffer = buf, nowait = true, desc = "Cancel" })
  vim.keymap.set("n", "y", function()
    close()
    on_yes()
  end, { buffer = buf, nowait = true, desc = "Confirm" })
end

return M
