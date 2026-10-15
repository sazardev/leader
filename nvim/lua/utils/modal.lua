-- ── Floating modals ─────────────────────────────────────────────────────────
-- Same flat style as the rest of the UI (ui/flat), the landing page's modal: a filled block, centered, the title in
-- capitals as its first row, folders blue, marks and keys yellow, hints faint, the input a `deep` bar.
-- Colors: the flat groups (ui/flat/groups.lua), or theme groups (base46) with `settings.ui.flat = false`.
--
-- Each line is a string, or a list of { text, hl } segments to paint
-- different parts of the same line (e.g. folder in one color, mark in another).
--
-- M.input   → text + editable field + buttons (Enter confirms, Esc cancels)
-- M.confirm → text + buttons (only y confirms, any other key cancels)
-- M.checklist → rows to switch on and off (Space/x, a for all) + buttons
local M = {}

local FLAT = require("ui.flat").enabled()

-- Modal groups → flat groups, or theme groups (see base46/integrations/nvimtree.lua)
local GROUPS = FLAT
    and {
      NvModalFolder = { link = "FlatFolder" },
      NvModalFile = { link = "NormalFloat" },
      NvModalTree = { link = "NormalFloat" },
      NvModalMark = { link = "FlatMark" },
      NvModalWarn = { link = "FlatWarn" },
      NvModalKey = { link = "FlatMark" },
      NvModalMuted = { link = "FlatModalHint" },
      NvModalBtn = { link = "FlatButton" },
      NvModalBtn2 = { link = "FlatButtonSoft" },
      NvModalBtnDanger = { link = "FlatButtonDanger" },
    }
  or {
    NvModalFolder = { link = "NvimTreeFolderName" },
    NvModalFile = { link = "Normal" },
    NvModalTree = { link = "NvimTreeIndentMarker" },
    NvModalMark = { link = "NvimTreeSpecialFile" },
    NvModalWarn = { link = "DiagnosticWarn" },
    NvModalKey = { link = "Special" },
    NvModalMuted = { link = "Comment" },
    NvModalBtn = { link = "PmenuSel" },
    NvModalBtn2 = { link = "Pmenu" },
    NvModalBtnDanger = { link = "ErrorMsg" },
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

--- Writes the lines into the buffer and paints them. The flat modal gives every row the block's color (not under the
--- buttons: a row-wide highlight wins over the chip's own background). Safe to call again to redraw
---@param buf integer
---@param lines (string|table[])[]
local function render(buf, lines)
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.tbl_map(plain, lines))
  paint(buf, lines)
  if FLAT then
    for i, line in ipairs(lines) do
      local chips = type(line) == "table"
        and vim.iter(line):any(function(seg)
          return type(seg[2]) == "string" and seg[2]:find "^NvModalBtn" ~= nil
        end)
      if not chips then
        vim.api.nvim_buf_set_extmark(buf, NS, i - 1, 0, { line_hl_group = "FlatModalRow", priority = 1 })
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
  render(buf, lines)
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
    title = opts.title and { { opts.title:upper() .. " ", "FlatModalTitle" } } or nil,
    title_pos = "left",
  })

  if FLAT then
    -- a new window inherits the window options of the one it opens from: from a picker (Move → new folder) the modal
    -- would carry the picker's `winhighlight`. The modal paints itself: every row on the block's color, none left to the
    -- window's own background
    vim.wo[win].winhighlight = "EndOfBuffer:NormalFloat"
    require("ui.flat.motion").enter { win }
  end

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true, desc = "Close" })
  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true, desc = "Close" })
  return buf, win, close
end

--- The row of buttons under a modal: small chips, a key and its word (`y Delete`, `n Cancel`), one cell of air on each side
---@param list { key: string, label: string, kind: "primary"|"soft"|"danger" }[]
---@return table line
local function buttons(list)
  local row = {}
  for i, b in ipairs(list) do
    local body = ({ primary = "NvModalBtn", soft = "NvModalBtn2", danger = "NvModalBtnDanger" })[b.kind]
    if i > 1 then
      row[#row + 1] = { "  " }
    end
    row[#row + 1] = { (" %s %s "):format(b.key, b.label), body }
  end
  return row
end

---@param lines (string|table[])[]
---@param opts { title?: string, default?: string, confirm?: string } `default` pre-fills the field; `confirm` names the button (Create, Rename…)
---@param on_submit fun(text: string)
function M.input(lines, opts, on_submit)
  local prompt = FLAT and " " or "> " -- flat: the field is a bar with a cell of air, like the demo's
  local default = opts.default or ""
  vim.list_extend(lines, FLAT and { { { prompt .. default } } } or { "", { { prompt, M.hl.key }, { default } } })
  local last = #lines
  lines[#lines + 1] = ""
  lines[#lines + 1] = buttons { -- what Enter and Esc do, as buttons under the field
    { key = "Enter", label = opts.confirm or "Confirm", kind = "primary" },
    { key = "Esc", label = "Cancel", kind = "soft" },
  }
  local buf, win, close = open(lines, { title = opts.title, editable = true })

  vim.api.nvim_win_set_cursor(win, { last, #prompt + #default })
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
    local line = vim.api.nvim_buf_get_lines(buf, last - 1, last, false)[1]
    -- the prompt is part of the line: wiping it (<C-u>, a visual delete) must not cost the first letter of what is typed
    local text = line:sub(1, #prompt) == prompt and line:sub(#prompt + 1) or line
    leave()
    on_submit(vim.trim(text))
  end
  vim.keymap.set({ "i", "n" }, "<CR>", submit, { buffer = buf, nowait = true, desc = "Submit" })
  vim.keymap.set("i", "<Esc>", leave, { buffer = buf, nowait = true, desc = "Close" })
end

---@param lines (string|table[])[]
---@param opts { title?: string, on_cancel?: fun(), confirm?: string, danger?: boolean } `on_cancel` runs when it closes without a yes (n, q, Esc); `confirm` names the yes button (Delete…), `danger` paints it red
---@param on_yes fun()
function M.confirm(lines, opts, on_yes)
  lines[#lines + 1] = ""
  lines[#lines + 1] = buttons {
    { key = "y", label = opts.confirm or "Yes", kind = opts.danger and "danger" or "primary" },
    { key = "n", label = "Cancel", kind = "soft" },
  }
  local buf, win, close = open(lines, { title = opts.title })

  local answered = false
  if opts.on_cancel then
    -- whichever way it closes (n, q, Esc, another window taking over), the caller hears about a no
    vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(win),
      once = true,
      callback = function()
        if not answered then
          answered = true
          vim.schedule(opts.on_cancel)
        end
      end,
    })
  end
  vim.keymap.set("n", "n", close, { buffer = buf, nowait = true, desc = "Cancel" })
  vim.keymap.set("n", "y", function()
    answered = true
    close()
    on_yes()
  end, { buffer = buf, nowait = true, desc = "Confirm" })
end

--- A list of things to switch on and off, then one button
--- Space or x toggles the row, a toggles all, Enter confirms, Esc/q cancels
---@param items { label: string, desc: string?, checked: boolean? }[]
---@param opts { title?: string, intro?: (string|table[])[], confirm?: string, footer?: string }
---@param on_submit fun(chosen: integer[]) the indexes of the checked items, in order
function M.checklist(items, opts, on_submit)
  local state = {}
  local label_w = 0
  for i, item in ipairs(items) do
    state[i] = item.checked and true or false
    label_w = math.max(label_w, vim.fn.strdisplaywidth(item.label))
  end
  local intro = opts.intro or {}
  local first = #intro + 1 -- the row of the first item

  local function lines()
    local out = vim.list_slice(intro)
    for i, item in ipairs(items) do
      local pad = string.rep(" ", label_w - vim.fn.strdisplaywidth(item.label))
      out[#out + 1] = {
        { state[i] and " [x] " or " [ ] ", state[i] and M.hl.mark or M.hl.muted },
        { item.label .. pad, state[i] and M.hl.file or M.hl.muted },
        { item.desc and ("  " .. item.desc) or "", M.hl.muted },
      }
    end
    out[#out + 1] = ""
    if opts.footer then
      out[#out + 1] = { { opts.footer, M.hl.muted } }
    end
    out[#out + 1] = buttons {
      { key = "Enter", label = opts.confirm or "Confirm", kind = "primary" },
      { key = "Esc", label = "Cancel", kind = "soft" },
    }
    return out
  end

  local buf, win = open(lines(), { title = opts.title })
  local last = first + #items - 1
  vim.wo[win].cursorline = true
  if FLAT then
    vim.wo[win].winhighlight = "EndOfBuffer:NormalFloat,CursorLine:FlatInput"
  end
  vim.api.nvim_win_set_cursor(win, { first, 0 })

  local function redraw()
    vim.bo[buf].modifiable = true
    render(buf, lines())
    vim.bo[buf].modifiable = false
  end
  local function row()
    return vim.api.nvim_win_get_cursor(win)[1]
  end
  local function toggle()
    local i = row() - first + 1
    if state[i] ~= nil then
      state[i] = not state[i]
      redraw()
    end
  end
  local function toggle_all()
    local any_off = vim.tbl_contains(state, false)
    for i in ipairs(state) do
      state[i] = any_off
    end
    redraw()
  end
  local function chosen()
    local out = {}
    for i, on in ipairs(state) do
      if on then
        out[#out + 1] = i
      end
    end
    return out
  end

  -- the cursor lives on the items only (not on the buttons under them)
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    callback = function()
      local r = row()
      if r < first or r > last then
        vim.api.nvim_win_set_cursor(win, { math.min(math.max(r, first), last), 0 })
      end
    end,
  })
  vim.keymap.set("n", "<Space>", toggle, { buffer = buf, nowait = true, desc = "Toggle" })
  vim.keymap.set("n", "x", toggle, { buffer = buf, nowait = true, desc = "Toggle" })
  vim.keymap.set("n", "a", toggle_all, { buffer = buf, nowait = true, desc = "Toggle all" })
  vim.keymap.set("n", "<CR>", function()
    local out = chosen()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    on_submit(out)
  end, { buffer = buf, nowait = true, desc = "Confirm" })
end

return M
