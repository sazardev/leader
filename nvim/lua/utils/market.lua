-- ── Full-screen marketplace ──────────────────────────────────────────────────
-- A list on the left, the thing under the cursor on the right, and a strip under both with what the choice will do. The
-- windows, the movement, the filter, folding groups, the help and the narrow-terminal layout live here; a spec says what the
-- rows are and what each pane shows (the SPEC.md modules, the STACK.md / DESIGN.md add-ons):
--   spec.rows(m)              the rows (group titles, spacers, items) for m.filter
--   spec.selectable(row)      a row the cursor can rest on
--   spec.list_line(row)       one row as segments `{ { text, hl }, … }`
--   spec.pane(m, row, width)  the lines of the right pane for the row, and optionally `rows` (line → anything, for keys)
--   spec.result(m)?           the lines of the "what it does" view (key `p`); no function = no such view
--   spec.summary(m)           the lines of the strip (the hint row is added)
--   spec.empty(m)?            text when no row matches (default: «Nothing matches …»)
--   spec.hints(m, mode)       `{ { key, word } }` for mode "list" | "pane" | "result"
--   spec.help                 `{ { key, text } }` listed by `?`, after the keys every market has
--   spec.keys                 `{ list = { { lhs, fn(m, row), desc } }, pane = { … }, all = { … } }`: they win over the base keys
--   spec.read(m, row)?        ⏎ in the list (default: the pane takes the focus)
--   spec.cancel(m)?           Esc / q in the list (default: close)
--   spec.initial(m)?          the row the cursor starts on (default: the first it can rest on)
--   spec.pane_click(m, item, line, column)?  a click on a pane line that `pane` returned in its `rows` (a choice, a checkbox)
--   spec.summary_rows         rows of the strip (default 7)
--   spec.live_input?          { prefix, placeholder, hl_prefix, hl_placeholder }: an editable one-line filter under the panes
--   spec.on_close(m)          when the market closes (save what it learned)
--   spec.hjkl                 l / → only move to the pane and h / ← back (⏎ alone reads): lists where reading does
--                             something big (the project picker opens the project)
-- Under 100 columns the panes take turns (the list, ⏎ opens the pane, Esc goes back) instead of sharing the screen.
-- The mouse (utils/mouse.lua): the row under the pointer is the one under the cursor (the pane follows), a click reads
-- it (or folds its group), and the key chips under the panes are buttons.
local modal = require "utils.modal"
local mouse = require "utils.mouse"

local M = {}

local NS = vim.api.nvim_create_namespace "Market"
local SEL = vim.api.nvim_create_namespace "MarketSel"
local HOVER = vim.api.nvim_create_namespace "MarketHover"
M.NARROW = 100

---@alias MarketSeg { [1]: string, [2]: string? }
---@alias MarketLine MarketSeg[]

---@class Market
---@field def table  the spec the market was opened with
---@field wins { list: integer, pane: integer, summary: integer }
---@field bufs { list: integer, pane: integer, summary: integer }
---@field rows table[]
---@field filter string
---@field view "pane"|"result"
---@field show "list"|"pane"   narrow terminals: what takes the screen
---@field collapsed table<string, boolean>
---@field pane_rows table<integer, any>
---@field input_return "list"|"pane"?

--- Word-wraps `text` to `width` display columns
---@param text string
---@param width integer
---@return string[]
function M.wrap(text, width)
  width = math.max(width, 10)
  local rows, row = {}, ""
  for word in text:gmatch "%S+" do
    if row == "" then
      row = word
    elseif vim.fn.strdisplaywidth(row .. " " .. word) <= width then
      row = row .. " " .. word
    else
      rows[#rows + 1] = row
      row = word
    end
  end
  rows[#rows + 1] = row
  return rows
end

---@param buf integer
---@param lines MarketLine[]
function M.draw(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, HOVER, 0, -1)
  vim.api.nvim_buf_set_lines(
    buf,
    0,
    -1,
    false,
    vim.tbl_map(function(line)
      return table.concat(vim.tbl_map(function(seg)
        return seg[1]
      end, line))
    end, lines)
  )
  for i, line in ipairs(lines) do
    local col = 0
    for _, seg in ipairs(line) do
      if seg[2] then
        vim.api.nvim_buf_set_extmark(buf, NS, i - 1, col, { end_col = col + #seg[1], hl_group = seg[2] })
      end
      col = col + #seg[1]
    end
  end
  vim.bo[buf].modifiable = false
end

--- Draws the optional live input without replacing its line while the user is typing.
---@param m Market
function M.draw_input(m)
  local buf, cfg = m.bufs.input, m.def.live_input
  if not buf or not cfg or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local query = m.filter or ""
  local prefix = cfg.prefix or "/ "
  local text = prefix .. query
  local current = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if not vim.deep_equal(current, { text }) then
    m.updating_input = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })
    m.updating_input = false
  end
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  vim.api.nvim_buf_set_extmark(buf, NS, 0, 0, { end_col = #prefix, hl_group = cfg.hl_prefix or "NvModalKey" })
  if query == "" then
    vim.api.nvim_buf_set_extmark(buf, NS, 0, #prefix, {
      virt_text = { { cfg.placeholder or "Filter…", cfg.hl_placeholder or "NvModalMuted" } },
      virt_text_pos = "inline",
    })
  end
end

--- Focuses the live input and enters Insert mode. `where` is where Enter returns.
---@param m Market
---@param where? "list"|"pane"
function M.focus_input(m, where)
  if not m.bufs.input or not vim.api.nvim_win_is_valid(m.wins.input) then
    return
  end
  m.input_return = where or (vim.api.nvim_get_current_win() == m.wins.pane and "pane" or "list")
  vim.api.nvim_set_current_win(m.wins.input)
  local prefix = m.def.live_input.prefix or "/ "
  vim.api.nvim_win_set_cursor(m.wins.input, { 1, #prefix + #(m.filter or "") })
  vim.cmd "startinsert!"
end

--- The row of key chips: a key and its word
---@param keys { [1]: string, [2]: string }[]
---@return MarketLine
function M.hints(keys)
  local line = { { " " } }
  for _, k in ipairs(keys) do
    line[#line + 1] = { (" %s "):format(k[1]), "NvModalBtn2" }
    line[#line + 1] = { " " .. k[2] .. "  ", modal.hl.muted }
  end
  return line
end

--- A row the cursor can rest on: the spec's items, and a folded group's title (to unfold it)
---@param m Market
---@param row table?
---@return boolean
local function selectable(m, row)
  return row ~= nil and (row.collapsed == true or m.def.selectable(row))
end

--- The rows of the spec with the folded groups cut to their title
---@param m Market
---@return table[]
local function visible_rows(m)
  local out, folded = {}, false
  for _, row in ipairs(m.def.rows(m)) do
    if row.group then
      folded = (m.filter or "") == "" and m.collapsed[row.group] == true
      row.collapsed = folded or nil
      out[#out + 1] = row
    elseif not folded or row.spacer or row.title then
      out[#out + 1] = row
    end
  end
  return out
end

---@param m Market
---@return table? row, integer index
function M.current(m)
  local at = vim.api.nvim_win_get_cursor(m.wins.list)[1]
  return m.rows[at], at
end

---@param m Market
function M.layout(m)
  local cols, rows = vim.o.columns, vim.o.lines - vim.o.cmdheight - 1 -- the statusline stays
  local strip = m.def.summary_rows or 7
  local input = m.def.live_input and 1 or 0
  local top = rows - strip - input
  local function cfg(row, col, width, height, hide)
    return { relative = "editor", row = row, col = col, width = width, height = height, hide = hide or false }
  end
  if cols < M.NARROW then
    local pane = m.show == "pane"
    vim.api.nvim_win_set_config(m.wins.list, cfg(0, 0, cols, top, pane))
    vim.api.nvim_win_set_config(m.wins.pane, cfg(0, 0, cols, top, not pane))
  else
    local left = math.min(44, math.floor(cols * 0.36))
    vim.api.nvim_win_set_config(m.wins.list, cfg(0, 0, left, top))
    vim.api.nvim_win_set_config(m.wins.pane, cfg(0, left, cols - left, top))
  end
  if input == 1 then
    vim.api.nvim_win_set_config(m.wins.input, cfg(top, 0, cols, 1))
  end
  vim.api.nvim_win_set_config(m.wins.summary, cfg(top + input, 0, cols, strip))
end

--- The row under the cursor stands out: the whole row lit and a bar at its left edge (the cursor block is hidden).
---@param m Market
local function mark_selection(m)
  if not vim.api.nvim_buf_is_valid(m.bufs.list) or not vim.api.nvim_win_is_valid(m.wins.list) then
    return
  end
  vim.api.nvim_buf_clear_namespace(m.bufs.list, SEL, 0, -1)
  local at = vim.api.nvim_win_get_cursor(m.wins.list)[1]
  if selectable(m, m.rows[at]) then
    pcall(vim.api.nvim_buf_set_extmark, m.bufs.list, SEL, at - 1, 0, {
      virt_text = { { "▌", "MarketBar" } },
      virt_text_pos = "overlay",
      priority = 200,
    })
  end
end

--- Draws everything from the state. `moved` = only the cursor moved: the list stays as it is (its rows are the
--- same), only the bar, the pane and the strip follow.
---@param m Market
---@param moved boolean?
---@param keep_input boolean?  do not redraw the editable input while TextChanged is running
function M.refresh(m, moved, keep_input)
  local w, spec = m.wins, m.def
  if not vim.api.nvim_win_is_valid(w.list) then
    return
  end
  if not moved then
    m.rows = visible_rows(m)
    local lines = vim.tbl_map(spec.list_line, m.rows)
    local any = false
    for _, row in ipairs(m.rows) do
      any = any or spec.selectable(row)
    end
    if not any then
      local text = spec.empty and spec.empty(m) or ("Nothing matches «" .. m.filter .. "»")
      lines[#lines + 1] = { { "  " .. text, modal.hl.muted } }
    end
    local at = vim.api.nvim_win_get_cursor(w.list)[1]
    M.draw(m.bufs.list, lines)
    pcall(vim.api.nvim_win_set_cursor, w.list, { math.min(at, math.max(#lines, 1)), 0 })
  end
  mark_selection(m)

  local row = m.rows[vim.api.nvim_win_get_cursor(w.list)[1]]
  local pane
  if m.view == "result" and spec.result then
    pane, m.pane_rows = spec.result(m), {}
  else
    pane, m.pane_rows = spec.pane(m, row, vim.api.nvim_win_get_width(w.pane))
    m.pane_rows = m.pane_rows or {}
  end
  M.draw(m.bufs.pane, pane)

  local strip = spec.summary_rows or 7
  local summary = spec.summary(m)
  while #summary < strip - 1 do
    summary[#summary + 1] = { { "" } }
  end
  local current = vim.api.nvim_get_current_win()
  local mode = (m.view == "result" and "result")
    or (current == w.pane or (current == w.input and m.input_return == "pane")) and "pane"
    or "list"
  local hints = M.hints(spec.hints(m, mode))
  summary[#summary + 1] = hints
  -- where each key chip sits, so a click on it does what the key does
  m.chips = {
    row = #summary,
    mode = mode,
    list = mouse.chips(hints, function(group)
      return group == "NvModalBtn2"
    end),
  }
  M.draw(m.bufs.summary, summary)
  if not keep_input then
    M.draw_input(m)
  end
end

---@param m Market
function M.close(m)
  if m.def and m.def.on_close and not m.closed then
    m.closed = true
    pcall(m.def.on_close, m)
  end
  for _, w in pairs(m.wins) do
    if vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim_win_close, w, true)
    end
  end
  require("utils.cursor").show(m)
end

--- Gives the focus to the list or the pane (in a narrow terminal it also swaps which one is on screen)
---@param m Market
---@param name "list"|"pane"
function M.focus(m, name)
  m.show = name
  M.layout(m)
  if vim.api.nvim_win_is_valid(m.wins[name]) then
    vim.api.nvim_set_current_win(m.wins[name])
  end
  vim.wo[m.wins.pane].cursorline = name == "pane"
  vim.wo[m.wins.list].cursorline = name == "list"
  M.refresh(m)
end

--- A small window listing keys; any of Esc, q, ? or ⏎ closes it
---@param title string
---@param rows { [1]: string, [2]: string }[]
function M.help(title, rows)
  local width = 0
  for _, r in ipairs(rows) do
    width = math.max(width, vim.fn.strdisplaywidth(r[1]))
  end
  local lines = { { { "  " .. title:upper(), modal.hl.key } }, { { "" } } }
  for _, r in ipairs(rows) do
    lines[#lines + 1] = {
      { " " .. r[1] .. string.rep(" ", width - vim.fn.strdisplaywidth(r[1])) .. " ", "NvModalBtn2" },
      { "  " .. r[2], modal.hl.muted },
    }
  end
  lines[#lines + 1] = { { "" } }
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  M.draw(buf, lines)
  local w = math.min(math.max(64, width + 30), vim.o.columns - 4)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.max(math.floor((vim.o.lines - #lines) / 2) - 1, 0),
    col = math.floor((vim.o.columns - w) / 2),
    width = w,
    height = #lines,
    style = "minimal",
    border = require("ui.flat").border(),
    zindex = 70,
  })
  if require("ui.flat").enabled() then
    vim.wo[win].winhighlight = "NormalFloat:NormalFloat,EndOfBuffer:NormalFloat"
  end
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  for _, k in ipairs { "<Esc>", "q", "?", "<CR>" } do
    vim.keymap.set("n", k, close, { buffer = buf, nowait = true, desc = "Close" })
  end
end

--- Opens the marketplace. `state` (optional) is the table the market lives in: a spec keeps its own fields on it
---@param spec table
---@param state table?
---@return Market
local function build(spec, state)
  local m = state or {}
  m.def = spec
  m.filter = m.filter or ""
  m.view = "pane"
  m.show = "list"
  m.collapsed = {}
  m.rows = {}
  m.pane_rows = {}
  m.input_return = "list"
  m.wins, m.bufs = {}, {}
  local names = { "list", "pane", "summary" }
  if spec.live_input then
    table.insert(names, 2, "input")
  end
  for _, name in ipairs(names) do
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "market"
    if name == "input" then
      vim.bo[buf].modifiable = true
      vim.b[buf].completion = false
    end
    m.bufs[name] = buf
  end
  local flat = require("ui.flat").enabled()
  local base =
    { relative = "editor", row = 0, col = 0, width = 10, height = 5, style = "minimal", border = "none", zindex = 40 }
  m.wins.pane = vim.api.nvim_open_win(m.bufs.pane, false, base)
  m.wins.summary = vim.api.nvim_open_win(m.bufs.summary, false, base)
  if spec.live_input then
    m.wins.input = vim.api.nvim_open_win(m.bufs.input, false, base)
  end
  m.wins.list = vim.api.nvim_open_win(m.bufs.list, true, base)
  -- the list and the strip are blocks (the modal's color); the reading pane is the editor's own deep color
  local block = flat and "NormalFloat:NormalFloat,EndOfBuffer:NormalFloat" or "NormalFloat:Pmenu"
  vim.wo[m.wins.list].winhighlight = block .. ",CursorLine:MarketSel"
  vim.wo[m.wins.summary].winhighlight = block
  if spec.live_input then
    vim.wo[m.wins.input].winhighlight = flat and "NormalFloat:FlatInput,EndOfBuffer:FlatInput" or "NormalFloat:Pmenu"
  end
  vim.wo[m.wins.pane].winhighlight = "NormalFloat:Normal,EndOfBuffer:Normal,CursorLine:FlatInput"
  for _, w in pairs(m.wins) do
    vim.wo[w].wrap = false
    vim.wo[w].cursorline = false
  end
  vim.wo[m.wins.list].cursorline = true
  -- the config's own cursorlineopt is "number": here the chosen row lights up whole
  vim.wo[m.wins.list].cursorlineopt = "line"
  vim.wo[m.wins.pane].cursorlineopt = "line"
  -- no cursor block over the list (the start screen's hidden cursor), back when the market closes
  require("utils.cursor").hide(m, "nv")
  M.layout(m)

  local function first()
    m.rows = visible_rows(m)
    local start = spec.initial and spec.initial(m)
    if start then
      return start
    end
    for i, r in ipairs(m.rows) do
      if selectable(m, r) then
        return i
      end
    end
    return 1
  end
  M.refresh(m) -- the list has to hold its lines before the cursor can be put on one
  pcall(vim.api.nvim_win_set_cursor, m.wins.list, { first(), 0 })
  M.refresh(m)

  -- movement: over titles and spacers to the next row the cursor can rest on
  local function move(step)
    local r = vim.api.nvim_win_get_cursor(m.wins.list)[1]
    for _ = 1, vim.v.count1 do
      local n = r + step
      while m.rows[n] and not selectable(m, m.rows[n]) do
        n = n + step
      end
      if not m.rows[n] then
        break
      end
      r = n
    end
    vim.api.nvim_win_set_cursor(m.wins.list, { r, 0 })
    m.view = "pane"
    M.refresh(m, true)
  end
  local function jump_group(step)
    local r = vim.api.nvim_win_get_cursor(m.wins.list)[1]
    local n = r + step
    while m.rows[n] and not m.rows[n].group do
      n = n + step
    end
    while m.rows[n] and not selectable(m, m.rows[n]) do
      n = n + 1
    end
    if selectable(m, m.rows[n]) then
      vim.api.nvim_win_set_cursor(m.wins.list, { n, 0 })
      m.view = "pane"
      M.refresh(m)
    end
  end
  --- Tab: folds the group the cursor is in (on a folded title it unfolds it)
  local function fold()
    local _, at = M.current(m)
    local g
    for i = at, 1, -1 do
      if m.rows[i] and m.rows[i].group then
        g = m.rows[i].group
        break
      end
    end
    if not g then
      return
    end
    m.collapsed[g] = not m.collapsed[g] or nil
    M.refresh(m)
    for i, r in ipairs(m.rows) do -- the cursor stays on the title when folding, on the first item when unfolding
      if r.group == g then
        local target = m.collapsed[g] and i or i + 1
        while m.rows[target] and not selectable(m, m.rows[target]) do
          target = target + 1
        end
        pcall(vim.api.nvim_win_set_cursor, m.wins.list, { math.min(target, #m.rows), 0 })
        break
      end
    end
    M.refresh(m)
  end
  local function filter()
    if spec.live_input then
      return M.focus_input(m, "list")
    end
    vim.ui.input({ prompt = "Filter: ", default = m.filter }, function(text)
      if text == nil then
        return
      end
      m.filter = vim.trim(text)
      m.rows = visible_rows(m)
      pcall(vim.api.nvim_win_set_cursor, m.wins.list, { first(), 0 })
      M.refresh(m)
    end)
  end
  local function result()
    if not spec.result then
      return
    end
    m.view = m.view == "result" and "pane" or "result"
    pcall(vim.api.nvim_win_set_cursor, m.wins.pane, { 1, 0 })
    if m.view == "result" then
      M.focus(m, "pane")
    else
      M.refresh(m)
    end
  end
  local function back()
    m.view = "pane"
    M.focus(m, "list")
  end
  local function help()
    local rows = {
      { "j k", "move" },
      { "{ }", "previous / next group" },
      { "Tab", "fold or unfold the group" },
      { "/", "filter (empty clears it)" },
      { "⏎ l", "read the one under the cursor (Esc or h goes back)" },
    }
    if spec.result then
      table.insert(rows, { "p", "what it does to the document, as it would read" })
    end
    vim.list_extend(rows, spec.help or {})
    rows[#rows + 1] = { "?", "this help" }
    M.help(spec.title or "Keys", rows)
  end

  local function map(buf, keys, fn, desc)
    for _, k in ipairs(type(keys) == "table" and keys or { keys }) do
      vim.keymap.set("n", k, fn, { buffer = buf, nowait = true, desc = desc })
    end
  end
  local lb, pb = m.bufs.list, m.bufs.pane
  map(lb, { "j", "<Down>" }, function()
    move(1)
  end, "Next")
  map(lb, { "k", "<Up>" }, function()
    move(-1)
  end, "Previous")
  map(lb, "}", function()
    jump_group(1)
  end, "Next group")
  map(lb, "{", function()
    jump_group(-1)
  end, "Previous group")
  map(lb, "<Tab>", fold, "Fold group")
  map(lb, "/", filter, "Filter")
  map(lb, "p", result, "What it does")
  map(lb, "?", help, "Help")
  if spec.hjkl then
    map(lb, { "l", "<Right>" }, function()
      pcall(vim.api.nvim_win_set_cursor, m.wins.pane, { 1, 0 })
      M.focus(m, "pane")
    end, "Details")
  end
  map(lb, spec.hjkl and { "<CR>" } or { "<CR>", "l", "<Right>" }, function()
    local row = M.current(m)
    if row and row.collapsed then
      return fold()
    end
    if spec.read then
      return spec.read(m, row)
    end
    pcall(vim.api.nvim_win_set_cursor, m.wins.pane, { 1, 0 })
    M.focus(m, "pane")
  end, "Read")
  map(lb, { "q", "<Esc>" }, function()
    if spec.cancel then
      return spec.cancel(m)
    end
    M.close(m)
  end, "Close")
  map(pb, "p", result, "What it does")
  map(pb, "?", help, "Help")
  map(pb, { "<Esc>", "q", "h", "<Left>" }, back, "Back")
  local extra = spec.keys or {}
  for _, name in ipairs { "list", "pane", "all" } do
    for _, k in ipairs(extra[name] or {}) do
      local bufs = name == "all" and { lb, pb, m.bufs.summary } or { name == "list" and lb or pb }
      for _, buf in ipairs(bufs) do
        map(buf, k[1], function()
          k[2](m, (M.current(m)))
        end, k[3])
      end
    end
  end

  local function leave_input(clear)
    vim.cmd "stopinsert"
    if clear then
      m.filter = ""
    end
    M.refresh(m)
    M.focus(m, m.input_return == "pane" and "pane" or "list")
  end
  if spec.live_input then
    local ib = m.bufs.input
    map(ib, { "i", "a" }, function()
      M.focus_input(m, m.input_return)
    end, "Edit filter")
    map(ib, { "<Esc>", "q" }, function()
      leave_input(false)
    end, "Back to mappings")
    vim.keymap.set("i", "<CR>", function()
      leave_input(false)
    end, { buffer = ib, nowait = true, desc = "Keep search" })
    vim.keymap.set("i", "<Esc>", function()
      leave_input(true)
    end, { buffer = ib, nowait = true, desc = "Clear search and go back" })
    vim.keymap.set("i", "<C-u>", function()
      local prefix = spec.live_input.prefix or "/ "
      m.updating_input = true
      vim.api.nvim_buf_set_lines(ib, 0, -1, false, { prefix })
      m.updating_input = false
      vim.api.nvim_win_set_cursor(m.wins.input, { 1, #prefix })
      m.filter = ""
      m.rows = visible_rows(m)
      pcall(vim.api.nvim_win_set_cursor, m.wins.list, { first(), 0 })
      M.refresh(m, false, true)
      M.draw_input(m)
    end, { buffer = ib, nowait = true, desc = "Clear search" })
  end

  -- the mouse, in every window (a click moves the focus to the one under the pointer before it arrives)
  local function read_row(line)
    pcall(vim.api.nvim_set_current_win, m.wins.list)
    pcall(vim.api.nvim_win_set_cursor, m.wins.list, { line, 0 })
    local row = m.rows[line]
    if row and row.collapsed then
      return fold()
    end
    if spec.read then
      return spec.read(m, row)
    end
    pcall(vim.api.nvim_win_set_cursor, m.wins.pane, { 1, 0 })
    M.focus(m, "pane")
  end
  local function clear_hover()
    if m.hover and vim.api.nvim_buf_is_valid(m.hover.buf) then
      pcall(vim.api.nvim_buf_clear_namespace, m.hover.buf, HOVER, 0, -1)
    end
    m.hover = nil
  end
  local function mark_hover(buf, line, from, to)
    clear_hover()
    if not vim.api.nvim_buf_is_valid(buf) or line < 1 then
      return
    end
    pcall(vim.api.nvim_buf_set_extmark, buf, HOVER, line - 1, from, {
      end_col = to,
      hl_group = "NvModalBtn",
      priority = 300,
    })
    m.hover = { buf = buf, line = line, from = from, to = to }
  end
  local handlers = {
    move = function(pos)
      if pos.winid == m.wins.list and selectable(m, m.rows[pos.line]) and mouse.follow(m.wins.list, pos.line) then
        clear_hover()
        m.view = "pane"
        M.refresh(m, true)
      elseif pos.winid == m.wins.pane and m.pane_rows[pos.line] ~= nil then
        mouse.follow(m.wins.pane, pos.line)
        local item = m.pane_rows[pos.line]
        local region = vim.iter(type(item) == "table" and item.actions or {}):find(function(action)
          return pos.column - 1 >= action.from and pos.column - 1 < action.to
        end)
        if region then
          mark_hover(m.bufs.pane, pos.line, region.from, region.to)
        else
          clear_hover()
        end
      elseif pos.winid == m.wins.summary and m.chips and pos.line == m.chips.row then
        local chip = vim.iter(m.chips.list):find(function(chip)
          return pos.column - 1 >= chip.from and pos.column - 1 < chip.to
        end)
        if chip then
          mark_hover(m.bufs.summary, pos.line, chip.from, chip.to)
        else
          clear_hover()
        end
      else
        clear_hover()
      end
    end,
    click = function(pos)
      if spec.live_input and pos.winid == m.wins.input then
        vim.api.nvim_set_current_win(m.wins.input)
        local prefix = spec.live_input.prefix or "/ "
        local line = vim.api.nvim_buf_get_lines(m.bufs.input, 0, 1, false)[1] or prefix
        vim.api.nvim_win_set_cursor(m.wins.input, { 1, math.min(math.max(pos.column - 1, #prefix), #line) })
        vim.cmd "startinsert!"
        return
      end
      if pos.winid == m.wins.list and m.rows[pos.line] and m.rows[pos.line].group then
        pcall(vim.api.nvim_set_current_win, m.wins.list)
        pcall(vim.api.nvim_win_set_cursor, m.wins.list, { pos.line, 0 })
        return fold()
      end
      if pos.winid == m.wins.list and selectable(m, m.rows[pos.line]) then
        return read_row(pos.line)
      end
      local item = pos.winid == m.wins.pane and m.pane_rows[pos.line]
      if item ~= nil and item ~= false and spec.pane_click then
        pcall(vim.api.nvim_set_current_win, m.wins.pane)
        pcall(vim.api.nvim_win_set_cursor, m.wins.pane, { pos.line, 0 })
        return spec.pane_click(m, item, pos.line, pos.column)
      end
      local chips = m.chips
      if pos.winid == m.wins.summary and chips and pos.line == chips.row then
        for _, chip in ipairs(chips.list) do
          if pos.column - 1 >= chip.from and pos.column - 1 < chip.to then
            local target = chips.mode == "pane" and m.wins.pane or m.wins.list
            pcall(vim.api.nvim_set_current_win, target)
            vim.api.nvim_feedkeys(vim.keycode(mouse.keys(chip.key)), "m", false)
            return
          end
        end
      end
    end,
  }
  for _, buf in pairs(m.bufs) do
    mouse.on(buf, handlers)
  end

  local group = vim.api.nvim_create_augroup("Market" .. m.bufs.list, { clear = true })
  if spec.live_input then
    vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
      buffer = m.bufs.input,
      group = group,
      callback = function()
        if m.updating_input or m.closed or not vim.api.nvim_buf_is_valid(m.bufs.input) then
          return
        end
        local prefix = spec.live_input.prefix or "/ "
        local line = vim.api.nvim_buf_get_lines(m.bufs.input, 0, 1, false)[1] or prefix
        local query = line:sub(1, #prefix) == prefix and line:sub(#prefix + 1) or line
        if line ~= prefix .. query then
          m.updating_input = true
          vim.api.nvim_buf_set_lines(m.bufs.input, 0, -1, false, { prefix .. query })
          vim.api.nvim_win_set_cursor(m.wins.input, { 1, #prefix + #query })
          m.updating_input = false
        end
        m.filter = query
        m.rows = visible_rows(m)
        pcall(vim.api.nvim_win_set_cursor, m.wins.list, { first(), 0 })
        M.refresh(m, false, true)
        M.draw_input(m)
      end,
    })
  end
  vim.api.nvim_create_autocmd("WinEnter", { -- in a narrow terminal what takes the screen follows the focus
    group = group,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      if win == m.wins.list or win == m.wins.pane then
        local name = win == m.wins.pane and "pane" or "list"
        if m.show ~= name then
          m.show = name
          M.layout(m)
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if vim.api.nvim_win_is_valid(m.wins.list) then
        M.layout(m)
        M.refresh(m)
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", { -- closing any of the three closes all
    group = group,
    pattern = vim.tbl_map(tostring, vim.tbl_values(m.wins)),
    once = true,
    callback = function()
      vim.schedule(function()
        M.close(m)
        pcall(vim.api.nvim_del_augroup_by_id, group)
      end)
    end,
  })
  return m
end

--- Opens it. When anything fails half way (a pane that raises, a bad row) nothing is left on screen: the windows are
--- closed, the cursor comes back, and the error is shown instead of a page that cannot be closed.
---@param spec table
---@param state table?
---@return Market?
function M.new(spec, state)
  state = state or {}
  local ok, result = pcall(build, spec, state)
  if ok then
    return result
  end
  pcall(M.close, state)
  require("utils.cursor").show(state)
  vim.notify("Leader: " .. tostring(result), vim.log.levels.ERROR)
  return nil
end

return M
