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
--   spec.hints(m, mode)       `{ { key, word } }` for mode "list" | "pane" | "result"
--   spec.help                 `{ { key, text } }` listed by `?`, after the keys every market has
--   spec.keys                 `{ list = { { lhs, fn(m, row), desc } }, pane = { … }, all = { … } }`: they win over the base keys
--   spec.read(m, row)?        ⏎ in the list (default: the pane takes the focus)
--   spec.cancel(m)?           Esc / q in the list (default: close)
--   spec.initial(m)?          the row the cursor starts on (default: the first it can rest on)
--   spec.pane_click(m, item, line, column)?  a click on a pane line that `pane` returned in its `rows` (a choice, a checkbox)
--   spec.summary_rows         rows of the strip (default 7)
-- Under 100 columns the panes take turns (the list, ⏎ opens the pane, Esc goes back) instead of sharing the screen.
-- The mouse (utils/mouse.lua): the row under the pointer is the one under the cursor (the pane follows), a click reads
-- it (or folds its group), and the key chips under the panes are buttons.
local modal = require "utils.modal"
local mouse = require "utils.mouse"

local M = {}

local NS = vim.api.nvim_create_namespace "Market"
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
      folded = m.collapsed[row.group] == true
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
  local top = rows - strip
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
  vim.api.nvim_win_set_config(m.wins.summary, cfg(top, 0, cols, strip))
end

--- Draws everything from the state
---@param m Market
function M.refresh(m)
  local w, spec = m.wins, m.def
  if not vim.api.nvim_win_is_valid(w.list) then
    return
  end
  m.rows = visible_rows(m)
  local lines = vim.tbl_map(spec.list_line, m.rows)
  local any = false
  for _, row in ipairs(m.rows) do
    any = any or spec.selectable(row)
  end
  if not any then
    lines[#lines + 1] = { { "  Nothing matches «" .. m.filter .. "»", modal.hl.muted } }
  end
  local at = vim.api.nvim_win_get_cursor(w.list)[1]
  M.draw(m.bufs.list, lines)
  pcall(vim.api.nvim_win_set_cursor, w.list, { math.min(at, math.max(#lines, 1)), 0 })

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
  while #summary < strip - 2 do
    summary[#summary + 1] = { { "" } }
  end
  summary[#summary + 1] = { { "" } }
  local mode = (m.view == "result" and "result") or (vim.api.nvim_get_current_win() == w.pane and "pane") or "list"
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
end

---@param m Market
function M.close(m)
  for _, w in pairs(m.wins) do
    if vim.api.nvim_win_is_valid(w) then
      pcall(vim.api.nvim_win_close, w, true)
    end
  end
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
function M.new(spec, state)
  local m = state or {}
  m.def = spec
  m.filter = m.filter or ""
  m.view = "pane"
  m.show = "list"
  m.collapsed = {}
  m.rows = {}
  m.pane_rows = {}
  m.wins, m.bufs = {}, {}
  for _, name in ipairs { "list", "pane", "summary" } do
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "market"
    m.bufs[name] = buf
  end
  local flat = require("ui.flat").enabled()
  local base = { relative = "editor", row = 0, col = 0, width = 10, height = 5, style = "minimal", border = "none", zindex = 40 }
  m.wins.pane = vim.api.nvim_open_win(m.bufs.pane, false, base)
  m.wins.summary = vim.api.nvim_open_win(m.bufs.summary, false, base)
  m.wins.list = vim.api.nvim_open_win(m.bufs.list, true, base)
  -- the list and the strip are blocks (the modal's color); the reading pane is the editor's own deep color
  local block = flat and "NormalFloat:NormalFloat,EndOfBuffer:NormalFloat" or "NormalFloat:Pmenu"
  vim.wo[m.wins.list].winhighlight = block .. ",CursorLine:FlatInput"
  vim.wo[m.wins.summary].winhighlight = block
  vim.wo[m.wins.pane].winhighlight = "NormalFloat:Normal,EndOfBuffer:Normal,CursorLine:FlatInput"
  for _, w in pairs(m.wins) do
    vim.wo[w].wrap = false
    vim.wo[w].cursorline = false
  end
  vim.wo[m.wins.list].cursorline = true
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
    M.refresh(m)
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
  map(lb, { "<CR>", "l", "<Right>" }, function()
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

  -- the mouse, in all three windows (a click moves the focus to the one under the pointer before it arrives)
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
  local handlers = {
    move = function(pos)
      if pos.winid == m.wins.list and selectable(m, m.rows[pos.line]) and mouse.follow(m.wins.list, pos.line) then
        m.view = "pane"
        M.refresh(m)
      elseif pos.winid == m.wins.pane and m.pane_rows[pos.line] ~= nil then
        mouse.follow(m.wins.pane, pos.line)
      end
    end,
    click = function(pos)
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

return M
