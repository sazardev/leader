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
-- M.checklist → rows to switch on and off (Space/x, a for all), optionally in groups (one-of groups) + buttons
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
local HOVER = vim.api.nvim_create_namespace "NvModalHover"
local mouse = require "utils.mouse"
---@type table<integer, table<integer, { from: integer, to: integer, key: string, group: string }[]>> per buffer: the button chips of each row
local BUTTONS = {}

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
  -- where the buttons are, for the mouse (a click on one does what its key does)
  BUTTONS[buf] = {}
  for i, line in ipairs(lines) do
    if type(line) == "table" then
      local chips = mouse.chips(line, function(group)
        return type(group) == "string" and group:find "^NvModalBtn" ~= nil
      end)
      if #chips > 0 then
        BUTTONS[buf][i] = chips
      end
    end
  end
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

--- The mouse on a modal: a button lights up under the pointer and a click presses its key; `hooks.hover(row)` and
--- `hooks.click(row)` (filled by the caller, e.g. the checklist) handle the other rows.
---@param buf integer
---@param win integer
---@param hooks { hover: fun(row: integer)?, click: fun(row: integer)? }
local function pointer(buf, win, hooks)
  local lit
  local function chip_at(pos)
    if pos.winid ~= win then
      return nil
    end
    for _, chip in ipairs((BUTTONS[buf] or {})[pos.line] or {}) do
      if pos.column - 1 >= chip.from and pos.column - 1 < chip.to then
        return chip
      end
    end
  end
  mouse.on(buf, {
    modes = { "n", "i" }, -- the input modal is typed into: its buttons answer in insert mode too
    move = function(pos)
      local chip = chip_at(pos)
      local key = chip and (pos.line .. ":" .. chip.from) or nil
      if key ~= lit then
        lit = key
        vim.api.nvim_buf_clear_namespace(buf, HOVER, 0, -1)
        if chip then
          -- the button under the pointer takes the primary color, like a hovered button anywhere
          vim.api.nvim_buf_set_extmark(buf, HOVER, pos.line - 1, chip.from, {
            end_col = chip.to,
            hl_group = chip.group == "NvModalBtnDanger" and "NvModalBtnDanger" or "NvModalBtn",
            priority = 300,
          })
        end
      end
      if not chip and pos.winid == win and hooks.hover then
        hooks.hover(pos.line)
      end
    end,
    click = function(pos)
      local chip = chip_at(pos)
      if chip then
        pcall(vim.api.nvim_set_current_win, win)
        return vim.api.nvim_feedkeys(vim.keycode(mouse.keys(chip.key)), "m", false)
      end
      if pos.winid == win and hooks.click then
        hooks.click(pos.line)
      end
    end,
  })
end

---@param lines (string|table[])[]
---@param opts { title?: string, editable?: boolean, hooks?: table }
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
  pointer(buf, win, opts.hooks or {})
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      BUTTONS[buf] = nil
    end,
  })
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
--- Space or x toggles the row, a toggles all, Enter confirms, Esc/q cancels. Items may carry a `group`: a title row is drawn
--- above each group (the cursor skips it), and in a group listed in `opts.exclusive` checking one unchecks the others
--- (pick one, or none). `a` never switches on more than one per exclusive group.
---@param items { label: string, desc: string?, checked: boolean?, group: string? }[]
--- `on_cancel`: Esc/q call it (the button reads "Back": a step of a longer flow). `clean`: dots instead of brackets and air
--- between groups (lists with groups that read better without the checkbox look).
---@param opts { title?: string, intro?: (string|table[])[], confirm?: string, footer?: string, exclusive?: table<string, boolean>, on_cancel?: fun(), clean?: boolean }
---@param on_submit fun(chosen: integer[]) the indexes of the checked items, in order
function M.checklist(items, opts, on_submit)
  local state = {}
  local label_w = 0
  local exclusive = opts.exclusive or {}
  for i, item in ipairs(items) do
    state[i] = item.checked and true or false
    label_w = math.max(label_w, vim.fn.strdisplaywidth(item.label))
  end
  local intro = opts.intro or {}

  -- the rows under the intro: a group title, or an item (its index)
  local rows = {}
  local group
  for i, item in ipairs(items) do
    if item.group and item.group ~= group then
      if opts.clean and group then
        rows[#rows + 1] = { spacer = true }
      end
      group = item.group
      rows[#rows + 1] = { title = item.group }
    end
    rows[#rows + 1] = { item = i }
  end
  local first = #intro + 1 -- the row of the first line of the list
  local last = first + #rows - 1
  ---@param r integer buffer row
  ---@return integer? item index
  local function item_at(r)
    local entry = rows[r - first + 1]
    return entry and entry.item
  end

  local function lines()
    local out = vim.list_slice(intro)
    for _, entry in ipairs(rows) do
      if entry.spacer then
        out[#out + 1] = ""
      elseif entry.title then
        out[#out + 1] = opts.clean and { { "  " .. entry.title:upper(), M.hl.muted } }
          or { { " " .. entry.title:upper(), M.hl.key }, { exclusive[entry.title] and "  one of" or "", M.hl.muted } }
      else
        local i, item = entry.item, items[entry.item]
        local pad = string.rep(" ", label_w - vim.fn.strdisplaywidth(item.label))
        local one = exclusive[item.group or ""]
        local box
        if opts.clean then
          box = state[i] and (one and "  ● " or "  ■ ") or (one and "  ○ " or "  □ ")
        else
          box = one and (state[i] and " (•) " or " ( ) ") or (state[i] and " [x] " or " [ ] ")
        end
        out[#out + 1] = {
          { box, state[i] and M.hl.mark or M.hl.muted },
          { item.label .. pad, state[i] and M.hl.file or M.hl.muted },
          { item.desc and ("  " .. item.desc) or "", M.hl.muted },
        }
      end
    end
    out[#out + 1] = ""
    if opts.footer then
      out[#out + 1] = { { opts.footer, M.hl.muted } }
    end
    out[#out + 1] = buttons {
      { key = "Enter", label = opts.confirm or "Confirm", kind = "primary" },
      { key = "Esc", label = opts.on_cancel and "Back" or "Cancel", kind = "soft" },
    }
    return out
  end

  local hooks = {}
  local buf, win, close = open(lines(), { title = opts.title, hooks = hooks })
  if opts.on_cancel then
    local function back()
      close()
      vim.schedule(opts.on_cancel)
    end
    vim.keymap.set("n", "<Esc>", back, { buffer = buf, nowait = true, desc = "Back" })
    vim.keymap.set("n", "q", back, { buffer = buf, nowait = true, desc = "Back" })
  end
  vim.wo[win].cursorline = true
  if FLAT then
    vim.wo[win].winhighlight = "EndOfBuffer:NormalFloat,CursorLine:FlatInput"
  end
  local start = first
  while start <= last and not item_at(start) do
    start = start + 1
  end
  vim.api.nvim_win_set_cursor(win, { start, 0 })

  local function redraw()
    vim.bo[buf].modifiable = true
    render(buf, lines())
    vim.bo[buf].modifiable = false
  end
  local function row()
    return vim.api.nvim_win_get_cursor(win)[1]
  end
  ---@param i integer
  ---@param on boolean
  local function set(i, on)
    state[i] = on
    local g = items[i].group
    if on and g and exclusive[g] then
      for j, other in ipairs(items) do
        if j ~= i and other.group == g then
          state[j] = false
        end
      end
    end
  end
  local function toggle()
    local i = item_at(row())
    if i then
      set(i, not state[i])
      redraw()
    end
  end
  -- the mouse: the item under the pointer is the one under the cursor, a click checks or unchecks it
  hooks.hover = function(r)
    if item_at(r) and r ~= row() then
      pcall(vim.api.nvim_win_set_cursor, win, { r, 0 })
    end
  end
  hooks.click = function(r)
    if item_at(r) then
      pcall(vim.api.nvim_win_set_cursor, win, { r, 0 })
      toggle()
    end
  end
  local function toggle_all()
    local any_off = false
    for i, item in ipairs(items) do
      if not state[i] and not exclusive[item.group or ""] then
        any_off = true
      end
    end
    for i, item in ipairs(items) do
      if exclusive[item.group or ""] then
        state[i] = any_off and state[i] or false -- all off clears them; all on leaves the choice as it is
      else
        state[i] = any_off
      end
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

  -- the cursor lives on the items only (not on group titles nor on the buttons under them)
  local prev = start
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = buf,
    callback = function()
      if #items == 0 then
        return
      end
      local r = math.min(math.max(row(), first), last)
      local step = r >= prev and 1 or -1
      while not item_at(r) do
        r = r + step
        if r > last or r < first then -- no item that way: go back the other way
          step = -step
          r = math.min(math.max(r, first), last)
        end
      end
      prev = r
      if r ~= row() then
        vim.api.nvim_win_set_cursor(win, { r, 0 })
      end
    end,
  })
  -- j/k go item to item (over the group titles) without waiting for CursorMoved to fix the row afterwards
  ---@param step integer
  local function move(step)
    local r = row()
    for _ = 1, vim.v.count1 do
      local nxt = r + step
      while nxt >= first and nxt <= last and not item_at(nxt) do
        nxt = nxt + step
      end
      if nxt < first or nxt > last then
        break
      end
      r = nxt
    end
    prev = r
    vim.api.nvim_win_set_cursor(win, { r, 0 })
  end
  for _, k in ipairs { "j", "<Down>" } do
    vim.keymap.set("n", k, function()
      move(1)
    end, { buffer = buf, nowait = true, desc = "Next" })
  end
  for _, k in ipairs { "k", "<Up>" } do
    vim.keymap.set("n", k, function()
      move(-1)
    end, { buffer = buf, nowait = true, desc = "Previous" })
  end
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
