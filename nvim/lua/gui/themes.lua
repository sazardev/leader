-- ── Desktop app: every theme, on the whole screen ────────────────────────────
-- utils/market.lua with the base46 catalog: on the left the terminal's theme and every dark and light theme, on the
-- right the one under the cursor drawn like the demo's editor (ui/flat/palette.lua derives the SAME tokens from the
-- theme's own tables, so the preview is what the flat design will really look like): its palette, an editor with
-- code, a diagnostic and the statusline, and a picker with a selection and a match. Nothing is applied while you
-- move; ⏎ applies and remembers it, Esc leaves yours. Rows, tokens and the preview lines are pure over the state.
local market = require "utils.market"
local modal = require "utils.modal"
local palette = require "ui.flat.palette"

local M = {}

local PV = "LeaderThemePv"
local made = {}

--- A highlight group for these colors, made on first use (the preview paints with colors of OTHER themes, so no
--- group of the config can be used).
---@param fg string?
---@param bg string?
---@param style string?  "b" bold, "i" italic
---@return string
local function hl(fg, bg, style)
  local name = ("%s_%s_%s_%s"):format(PV, (fg or "x"):gsub("#", ""), (bg or "x"):gsub("#", ""), style or "")
  if not made[name] then
    made[name] = true
    vim.api.nvim_set_hl(0, name, { fg = fg, bg = bg, bold = style == "b" or nil, italic = style == "i" or nil })
  end
  return name
end

--- The names of the base46 themes, sorted.
---@return string[]
function M.names()
  local out = {}
  for _, file in ipairs(vim.api.nvim_get_runtime_file("lua/base46/themes/*.lua", true)) do
    out[#out + 1] = vim.fn.fnamemodify(file, ":t:r")
  end
  table.sort(out)
  return out
end

--- Tokens of a theme read from its own tables (nothing is applied). Cached on the market.
---@param m table
---@param name string
---@return FlatTokens?
function M.tokens(m, name)
  m.cache = m.cache or {}
  if m.cache[name] == nil then
    local ok, tokens = pcall(function()
      if name == "terminal" then
        local loaded = require("appearance.alacritty").load()
        local theme = require("appearance.terminal_theme").build(
          loaded.palette,
          require("core.settings").theme.terminal.min_contrast
        )
        return palette.from(theme.base_16, theme.base_30, { faithful = true, selection = loaded.palette.selection })
      end
      local theme = require("base46.themes." .. name)
      return palette.from(theme.base_16, theme.base_30)
    end)
    m.cache[name] = ok and tokens or false
  end
  return m.cache[name] or nil
end

--- The rows: the terminal's theme, then dark and light (pure over m.names, m.kind, m.before, m.filter).
---@param m table
---@return table[]
function M.rows(m)
  local rows = { { title = "ALL THEMES" }, { spacer = true } }
  local function add(group, names)
    names = vim.tbl_filter(function(name)
      return m.filter == "" or name:lower():find(m.filter:lower(), 1, true) ~= nil
    end, names)
    if #names == 0 then
      return
    end
    rows[#rows + 1] = { group = group }
    for _, name in ipairs(names) do
      rows[#rows + 1] = { theme = name, current = name == m.before }
    end
    rows[#rows + 1] = { spacer = true }
  end
  add("Terminal", m.terminal and { "terminal" } or {})
  add(
    "Dark",
    vim.tbl_filter(function(n)
      return m.kind[n] == "dark"
    end, m.names)
  )
  add(
    "Light",
    vim.tbl_filter(function(n)
      return m.kind[n] == "light"
    end, m.names)
  )
  return rows
end

function M.selectable(row)
  return row.theme ~= nil
end

---@param m table
---@param row table
---@return MarketLine
function M.list_line(row, m)
  if row.title then
    return { { "  " .. row.title, modal.hl.key } }
  elseif row.spacer then
    return { { "" } }
  elseif row.group then
    return { { (row.collapsed and "▸ " or "  ") .. row.group:upper(), modal.hl.muted } }
  end
  local line = { { row.current and "  ● " or "    ", modal.hl.mark }, { row.theme, modal.hl.file } }
  local t = m and M.tokens(m, row.theme)
  if t then
    -- the accents as little squares, on the surface the list is painted with
    local pad = string.rep(" ", math.max(20 - vim.fn.strdisplaywidth(row.theme), 1))
    line[#line + 1] = { pad }
    for _, c in ipairs { t.red, t.orange, t.yellow, t.green, t.aqua, t.blue, t.purple } do
      line[#line + 1] = { "■", hl(c, nil) }
    end
  end
  return line
end

-- ── the preview ──────────────────────────────────────────────────────────────

--- A line of the preview: `segs` over `bg`, padded to `width` display columns with that bg.
---@param segs table[]  { text, fg, style? }[]
---@param bg string
---@param width integer
---@param margin integer? cells of the page left and right of the block
---@param page string? the page's bg (the margin)
---@return MarketLine
local function block(segs, bg, width, margin, page)
  margin = margin or 0
  local line = { { string.rep(" ", margin) } }
  local used = 0
  for _, s in ipairs(segs) do
    line[#line + 1] = { s[1], hl(s[2], s[4] or bg, s[3]) }
    used = used + vim.fn.strdisplaywidth(s[1])
  end
  local inner = width - 2 * margin
  line[#line + 1] = { string.rep(" ", math.max(inner - used, 0)), hl(nil, bg) }
  return line
end

--- The preview of a theme as lines (pure over the tokens and the size).
---@param t FlatTokens
---@param name string
---@param opts { width: integer, current: boolean? }
---@return MarketLine[]
function M.preview(t, name, opts)
  local width = opts.width
  local out = {}
  local margin = 2
  local inner = width - 2 * margin
  local function page(text, fg, style)
    return { { "  " .. (text or ""), hl(fg or t.fg, t.bg, style) } }
  end
  local function blank()
    out[#out + 1] = { { "", hl(t.fg, t.bg) } }
  end
  local function ed(segs, bg)
    out[#out + 1] = block(segs, bg or t.deep, width, margin, t.bg)
  end

  blank()
  local title = page(name, t.fg, "b")
  title[#title + 1] = { "   " .. (t.dark and "dark" or "light"), hl(t.dim, t.bg) }
  if opts.current then
    title[#title + 1] = { "   ● in use", hl(t.green, t.bg) }
  end
  out[#out + 1] = title
  blank()

  -- the palette: the accents as solid chips, then the surfaces
  local chips = { { "  ", hl(t.fg, t.bg) } }
  for _, c in ipairs { t.red, t.orange, t.yellow, t.green, t.aqua, t.blue, t.purple } do
    chips[#chips + 1] = { "      ", hl(t.on, c) }
    chips[#chips + 1] = { " ", hl(t.fg, t.bg) }
  end
  out[#out + 1] = chips
  out[#out + 1] = chips
  blank()
  local surfaces = { { "  ", hl(t.fg, t.bg) } }
  for _, c in ipairs { t.deep, t.soft, t.faint, t.dim, t.fg } do
    surfaces[#surfaces + 1] = { "      ", hl(t.fg, c) }
    surfaces[#surfaces + 1] = { " ", hl(t.fg, t.bg) }
  end
  out[#out + 1] = surfaces
  blank()

  -- the editor: tab line, code, a diagnostic, statusline
  ed({ { " main.go ", t.fg, nil, t.deep }, { " handler.go ", t.dim, nil, t.soft } }, t.soft)
  local function num(n, cur)
    return { ("%3d  "):format(n), cur and t.fg or t.faint, nil, nil }
  end
  local code = {
    { num(1), { "package", t.purple }, { " main", t.fg } },
    { num(2) },
    { num(3), { "// serve answers the health check", t.faint, "i" } },
    {
      num(4),
      { "func", t.purple },
      { " serve", t.blue },
      { "(w ", t.fg },
      { "http.ResponseWriter", t.yellow },
      { ") {", t.fg },
    },
    {
      num(5, true),
      { "    count", t.fg },
      { " := ", t.aqua },
      { "42", t.orange },
      { "  ", t.fg },
      { "● unused variable", t.red, "i" },
    },
    {
      num(6),
      { "    fmt", t.fg },
      { ".", t.aqua },
      { "Fprintf", t.blue },
      { "(w, ", t.fg },
      { '"ok %d"', t.green },
      { ", count)", t.fg },
    },
    { num(7), { "}", t.fg } },
  }
  for i, segs in ipairs(code) do
    -- the cursor line rests on a veil of the foreground
    local bg = i == 5 and palette.veil(t, t.fg, 0.07) or t.deep
    ed(
      vim.tbl_map(function(s)
        return { s[1], s[2], s[3], bg }
      end, segs),
      bg
    )
  end
  -- statusline: mode chip, file, then the pills on the right
  local left = {
    { " NORMAL ", t.on, "b", t.blue },
    { "  main.go ", t.fg, nil, t.soft },
    { " master ", t.dim, nil, t.soft },
  }
  local right = {
    { " E1 ", t.on, nil, t.red },
    { " ", t.fg, nil, t.soft },
    { " W2 ", t.on, nil, t.yellow },
    { "  5:12 ", t.dim, nil, t.soft },
  }
  local used = 0
  for _, s in ipairs(left) do
    used = used + vim.fn.strdisplaywidth(s[1])
  end
  for _, s in ipairs(right) do
    used = used + vim.fn.strdisplaywidth(s[1])
  end
  local row = vim.list_extend({}, left)
  row[#row + 1] = { string.rep(" ", math.max(inner - used, 1)), t.fg, nil, t.soft }
  vim.list_extend(row, right)
  ed(row, t.soft)
  blank()

  -- a picker: soft block, the selection solid blue, the match yellow
  local function pick(segs, bg)
    ed(segs, bg)
  end
  pick({ { "  Find files ", t.faint, "b" }, { "  han", t.fg } }, t.soft)
  pick(
    { { "  ", t.fg, nil, t.blue }, { "handler.go", t.on, "b", t.blue }, { "  internal/http", t.on, nil, t.blue } },
    t.blue
  )
  pick({ { "  ", t.fg }, { "han", t.yellow, "b" }, { "dler_test.go", t.fg }, { "  internal/http", t.faint } }, t.soft)
  pick({ { "  ", t.fg }, { "han", t.yellow, "b" }, { "gup.go", t.fg }, { "  cmd/server", t.faint } }, t.soft)
  return out
end

---@param m table
---@param row table
---@param width integer
---@return MarketLine[]
function M.pane(m, row, width)
  local t = row and row.theme and M.tokens(m, row.theme)
  if not t then
    return {}
  end
  -- the pane is the theme's own page, whatever the rest of the screen is painted with
  if m.wins and vim.api.nvim_win_is_valid(m.wins.pane) then
    local page = hl(t.fg, t.bg)
    vim.wo[m.wins.pane].winhighlight = ("NormalFloat:%s,EndOfBuffer:%s,CursorLine:%s"):format(page, page, page)
  end
  return M.preview(t, row.theme, { width = width, current = row.current })
end

function M.summary(m)
  local dark, light = 0, 0
  for _, name in ipairs(m.names) do
    if m.kind[name] == "light" then
      light = light + 1
    else
      dark = dark + 1
    end
  end
  return {
    { { ("  %d themes · %d dark · %d light"):format(#m.names, dark, light), modal.hl.muted } },
    { { "  In use: " .. m.before, modal.hl.muted } },
  }
end

function M.hints(_, mode)
  if mode == "pane" then
    return { { "h ← Esc", "back" }, { "⏎", "apply" } }
  end
  return {
    { "↑↓ jk", "move" },
    { "⏎", "apply" },
    { "Tab", "fold" },
    { "/", "filter" },
    { "?", "keys" },
    { "Esc", "keep mine" },
  }
end

---@param name string
local function apply(name)
  local appearance = require "appearance"
  if appearance.current() ~= name and appearance.use(name) then
    require("utils.log").info("Theme: " .. name)
  end
end

--- The market's state before it opens (pure data: names, light or dark, what is in use).
---@return table
function M.state()
  local appearance = require "appearance"
  local names, kind = {}, {}
  for _, name in ipairs(M.names()) do
    if name ~= "terminal" then
      local ok, theme = pcall(require, "base46.themes." .. name)
      if ok then
        names[#names + 1] = name
        kind[name] = theme.type == "light" and "light" or "dark"
      end
    end
  end
  local terminal = require("core.settings").theme.terminal.enabled and require("appearance.alacritty").load() ~= nil
  return {
    names = names,
    kind = kind,
    terminal = terminal,
    before = appearance.current(),
  }
end

function M.open()
  local def = {
    title = "All themes",
    rows = M.rows,
    selectable = M.selectable,
    list_line = function(row)
      return M.list_line(row, M.active)
    end,
    pane = M.pane,
    summary = M.summary,
    hints = M.hints,
    summary_rows = 4,
    read = function(m, row)
      if row and row.theme then
        market.close(m)
        apply(row.theme)
      end
    end,
    initial = function(m)
      for i, r in ipairs(m.rows) do
        if r.current then
          return i
        end
      end
    end,
    help = {
      { "⏎", "apply the theme and keep it for the next start" },
      { "Esc", "close and leave the theme you had" },
    },
    on_close = function()
      M.active = nil
    end,
  }
  local state = M.state()
  M.active = state
  local m = market.new(def, state)
  if not m then
    M.active = nil
  end
  return m
end

return M
