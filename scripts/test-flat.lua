-- Tests of the flat design (nvim/lua/ui/flat): tokens and highlight groups. Pure: they need no plugins or config.
--   nvim -u NONE --headless -c "luafile scripts/test-flat.lua"
local root = vim.env.AGENT_TEST_ROOT or vim.fn.getcwd()
vim.opt.rtp:prepend(root .. "/nvim")
package.path = root .. "/nvim/lua/?.lua;" .. root .. "/nvim/lua/?/init.lua;" .. package.path

local color = require "appearance.color"
local palette = require "ui.flat.palette"
local groups = require "ui.flat.groups"
local terminal_theme = require "appearance.terminal_theme"

local fails, total = 0, 0
local function check(cond, msg)
  total = total + 1
  if not cond then
    fails = fails + 1
    print("FAIL " .. msg)
  end
end

-- terminal palettes (bg, fg, ANSI 0-15) the way theme files ship them: the same path the real terminal theme takes
local PALETTES = {
  gruvbox = { "#282828", "#ebdbb2", { "#282828", "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a", "#a89984", "#928374", "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c", "#ebdbb2" } },
  tokyo = { "#1a1b26", "#c0caf5", { "#15161e", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#a9b1d6", "#414868", "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff", "#c0caf5" } },
  nord = { "#2e3440", "#d8dee9", { "#3b4252", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0", "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4" } },
  latte = { "#eff1f5", "#4c4f69", { "#5c5f77", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#acb0be", "#6c6f85", "#d20f39", "#40a02b", "#df8e1d", "#1e66f5", "#ea76cb", "#179299", "#bcc0cc" } },
  solarized_light = { "#fdf6e3", "#657b83", { "#073642", "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198", "#eee8d5", "#002b36", "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1", "#fdf6e3" } },
}

local REQUIRED = {
  "NormalFloat", "FloatBorder", "FloatTitle", "Pmenu", "PmenuSel", "WinSeparator",
  "BlinkCmpMenu", "BlinkCmpMenuSelection", "BlinkCmpDoc", "BlinkCmpSignatureHelpActiveParameter",
  "WhichKey", "WhichKeyGroup", "WhichKeyDesc", "WhichKeyNormal",
  "TelescopeSelection", "TelescopePromptNormal", "TelescopeResultsNormal", "TelescopePreviewNormal", "TelescopeMatching",
  "NvimTreeNormal", "NvimTreeRootFolder", "Visual", "CursorLineNr", "DiffAdd", "DiffDelete", "GitConflictCurrent",
  "TelescopePreviewLine", "TelescopePreviewMatch", "FlashLabel", "MultiCursorCursor", "GrugFarResultsMatchRemoved", "FlatNotify", "FlatNotifyError", "FlatKey", "NvStartNormal", "NvStartSel", "NvStartBtn",
  "AgentInput", "AgentStatus", "AgentFloat", "CommitHeader", "CommitAI", "FlatFresh1", "FlatFresh" .. groups.FRESH_STEPS,
}

for name, p in pairs(PALETTES) do
  local tb = terminal_theme.build({ background = p[1], foreground = p[2], ansi = p[3] }, 3.0)
  local t = palette.from(tb.base_16, tb.base_30)
  local g = groups.build(t)

  for _, group in ipairs(REQUIRED) do
    check(g[group] ~= nil, name .. ": missing group " .. group)
  end

  -- a float is a block ONE step above the background; its border cells are painted like the block (padding, not a line)
  check(color.contrast(t.soft, t.bg) > 1.02 and color.contrast(t.soft, t.bg) < 1.5, name .. ": `soft` must be a subtle step over the background")
  check(g.FloatBorder.fg == g.NormalFloat.bg and g.FloatBorder.bg == g.NormalFloat.bg, name .. ": FloatBorder must be invisible")
  check(g.WhichKeyBorder.bg == g.WhichKeyNormal.bg, name .. ": which-key border must match its block")
  -- the editor is `deep` (the demo's editor); the half-cell edges are block over editor; titles sit inside the blocks
  check(g.Normal.bg == t.deep, name .. ": the editor surface is `deep`")
  check(g.FlatEdge.fg == t.soft and g.FlatEdge.bg == t.deep, name .. ": half-cell edges are block over editor")
  check(g.TelescopeResultsTitle.bg == t.soft and g.TelescopePromptTitle.bg == t.soft, name .. ": telescope titles sit inside their blocks")
  check(g.FlatTerm.bg == t.bg, name .. ": the terminal float is one step over the editor (the theme's own bg)")

  -- readability: selection text over the blue, keys and matches over the block, hints over the block
  check(color.contrast(t.on, t.blue) >= 3.0, name .. ": selected text unreadable (" .. color.contrast(t.on, t.blue) .. ")")
  check(color.contrast(t.yellow, t.soft) >= 2.5, name .. ": yellow keys unreadable over the block")
  check(color.contrast(g.NvimTreeHiddenFileHL.fg, t.deep) >= 3.0, name .. ": hidden files unreadable in the tree")
  check(g.NvimTreeHiddenFileHL.fg ~= g.NvimTreeFolderName.fg and g.NvimTreeHiddenFileHL.fg ~= t.fg, name .. ": hidden files must have a color of their own")
  -- the modal's buttons: their text readable on the chip, and each chip visible over the block it sits on
  check(color.contrast(g.FlatButton.fg, g.FlatButton.bg) >= 3.0, name .. ": primary button text unreadable")
  check(color.contrast(g.FlatButtonDanger.fg, g.FlatButtonDanger.bg) >= 2.5, name .. ": danger button text unreadable")
  check(color.contrast(g.FlatButtonSoft.fg, g.FlatButtonSoft.bg) >= 3.0, name .. ": soft button text unreadable")
  check(color.contrast(g.FlatButtonSoft.bg, t.soft) >= 1.05, name .. ": the soft button vanishes into the block")
  check(color.contrast(t.dim, t.soft) >= 3.5, name .. ": dim text unreadable over the block")
  check(color.contrast(t.faint, t.soft) >= 1.9, name .. ": faint hints vanish over the block")

  -- text is never chipped: TODO/NOTE and quotes carry no background; the preview's hit line stays a veil the text can be read over
  for _, group in ipairs { "Todo", "@comment.todo", "@comment.note", "@markup.quote" } do
    check(g[group] and g[group].bg == nil, name .. ": " .. group .. " must not paint a background")
  end
  check(color.contrast(t.dim, g.TelescopePreviewLine.bg) >= 3.0, name .. ": text unreadable over the preview's hit line")

  -- the "just changed" flash fades: each frame is closer to the background than the one before
  local function distance(i)
    local bg = g["FlatFresh" .. i].bg
    return math.abs(color.luminance(bg) - color.luminance(t.deep))
  end
  for i = 2, groups.FRESH_STEPS do
    check(distance(i) < distance(i - 1) + 1e-9, name .. ": flash frame " .. i .. " does not fade")
  end

  -- added / removed lines are veils (close to the background), never solid colors
  check(color.contrast(g.DiffAdd.bg, t.deep) < 1.6, name .. ": DiffAdd must be a veil")
  -- (the theme's own text contrast is its business: the veil may only cost a little of it)
  check(color.contrast(t.fg, g.DiffAdd.bg) >= math.min(4.5, 0.7 * color.contrast(t.fg, t.bg)), name .. ": text over DiffAdd unreadable")
end

-- rebase: groups painted with the theme bg move to the editor surface; links, ours and other colors stay
do
  local all = {
    LineNr = { fg = 0x665c54, bg = 0x282828 },
    Hidden = { fg = 0x282828 },
    Linked = { link = "Normal" },
    Other = { fg = 0x111111, bg = 0x333333 },
    Ours = { bg = 0x282828 },
  }
  local out = groups.rebase(all, 0x282828, 0x202020, { Ours = true })
  check(out.LineNr and out.LineNr.bg == 0x202020 and out.LineNr.fg == 0x665c54, "rebase: bg moves, fg stays")
  check(out.Hidden and out.Hidden.fg == 0x202020, "rebase: a character hidden with fg = bg stays hidden")
  check(out.Linked == nil and out.Other == nil and out.Ours == nil, "rebase: links, other colors and our own groups untouched")
  check(all.LineNr.bg == 0x282828, "rebase: pure (the input is not modified)")
end

-- telescope layout (ui/flat/telescope.lua): pure geometry
do
  local tel = require "ui.flat.telescope"
  local wide = tel.geometry(120, 33, true)
  check(wide.side and wide.preview ~= nil, "telescope: preview beside the list on a wide screen")
  check(wide.prompt.row == wide.results.row + wide.results.height + 2, "telescope: the prompt sits right under the results")
  check(wide.preview.col == wide.results.col + wide.results.width, "telescope: the preview starts where the list ends (the gap is its edge)")
  check(wide.results.col + wide.results.width + wide.preview.width + 2 <= 120 - 2, "telescope: two columns of editor stay at the right")
  check(wide.prompt.row + 1 + 1 <= 33 - 1, "telescope: one row of editor stays under the frame")
  local narrow = tel.geometry(70, 33, true)
  check(not narrow.side and narrow.preview.row < narrow.results.row, "telescope: narrow screen puts the preview above the list")
  local none = tel.geometry(120, 33, false)
  check(none.preview == nil and none.results.width == 116, "telescope: without a previewer the list takes the width")
  local chooser = tel.geometry(120, 33, false, 6)
  check(chooser.results.height == 6 and chooser.results.width <= 90, "telescope: a short chooser gets a block as tall as its list")
  check(chooser.results.col > 2 and chooser.results.row > 1, "telescope: the chooser block is centered")
  check(tel.geometry(120, 33, false, 200).results.height == 33 - 2 - 5, "telescope: a long list keeps the full frame")
end

-- which-key panel (ui/flat/whichkey.lua): the grid fills rows first
do
  local wk = require "ui.flat.whichkey"
  local items = {}
  for i, k in ipairs { "a", "C", "f", "g", "G", "/" } do
    items[i] = { key = k, desc = "item " .. k, group = i <= 5 }
  end
  local rows, n = wk.grid(items, 120)
  check(n == 4 and #rows == 2, "whichkey: 4 columns on a wide screen, rows of 4")
  check(rows[1][2][1] == "a" and rows[1][6][1] == "C" and rows[2][2][1] == "G", "whichkey: filled row by row (a C f g / G /)")
  check(rows[1][4][2] == "WhichKeyGroup" and rows[2][8][2] == "WhichKeyDesc", "whichkey: groups purple, actions dim")
  local _, n2 = wk.grid(items, 80)
  check(n2 == 2, "whichkey: 2 columns on a narrow screen")
  local long = wk.grid({ { key = "x", desc = ("long "):rep(20), group = false } }, 120)
  check(vim.fn.strdisplaywidth(long[1][4][1]) < 30 and long[1][4][1]:find "…$", "whichkey: long labels are cut with …")
end

-- motion (ui/flat/motion.lua): the slide starts `rise` rows low, lands exactly in place and never goes back up
do
  local motion = require "ui.flat.motion"
  check(motion.offset(2, 0, 5) == 2 and motion.offset(2, 5, 5) == 0, "motion: starts low, lands in place")
  local prev = 2
  for f = 1, 5 do
    local o = motion.offset(2, f, 5)
    check(o <= prev and o >= 0, "motion: the slide only moves up")
    prev = o
  end
end

-- the notifier must not break without a UI (headless): it falls back to the original vim.notify
local original = vim.notify
local seen
vim.notify = function(msg)
  seen = msg
end
require("ui.flat.notify").setup()
vim.notify("hello", vim.log.levels.INFO)
check(seen == "hello", "notify without a UI must reach the original vim.notify")
vim.notify = original

-- start screen layout (ui/start/layout.lua): pure
local start = require "ui.start.layout"
local ACTIONS = { { label = "Find File", key = "ff" }, { label = "Recent Files", key = "fo" }, { label = "Find Word", key = "fw" }, { label = "Themes", key = "th" }, { label = "Mappings", key = "ch" }, { label = "Change Art", key = "ca" } }
local ART = {}
for i = 1, 10 do
  ART[i] = "⠀⠀⠀⣿⣿⣿⠀⠀"
end
local function screen(w, h, extra)
  local opts = vim.tbl_extend("force", { width = w, height = h, art = ART, repo = "proj (main)", user = "Omar", actions = ACTIONS, sel = 2 }, extra or {})
  return start.compute(opts)
end
local lines, spans, rows = screen(110, 40)
check(#rows == #ACTIONS, "start: one row per button")
check(lines[rows[1] + 2]:find "▀" ~= nil, "start: each button ends in a half-cell edge")
local plain_lines, _, plain_rows = screen(110, 40, { edges = false })
check(vim.trim(plain_lines[plain_rows[1] + 2]) == "", "start: without the flat design the gap is a blank row")
for i = 2, #rows do
  check(rows[i] - rows[i - 1] == 2, "start: a blank row between buttons when there is room")
end
check(#lines <= 40, "start: fits the window")
local sel_spans = vim.tbl_filter(function(s) return s.hl == "NvStartSel" end, spans)
check(#sel_spans == 1 and sel_spans[1].row == rows[2], "start: exactly the selected button is NvStartSel")
local widths = {}
for i, r in ipairs(rows) do
  widths[i] = vim.fn.strdisplaywidth(lines[r + 1])
end
check(widths[1] == widths[2] and widths[2] == widths[6], "start: every button has the same width")
local _, _, rows_small, compact = screen(80, 24)
check(compact and rows_small[2] - rows_small[1] == 1, "start: short window drops the gaps between buttons")
local lines_tiny = screen(40, 10)
check(#lines_tiny <= 10, "start: a tiny window drops the art and still fits (" .. #lines_tiny .. " rows)")
local lines_narrow = screen(20, 30)
for _, l in ipairs(lines_narrow) do
  check(vim.fn.strdisplaywidth(l) <= 20, "start: nothing wider than a narrow window")
end

-- ── which-key labels: no section the menu already says ───────────────────────
local labels = require "ui.flat.labels"
local LABELS = {
  { "Go", "Go run", "run" },
  { "Go", "Go test -race ./...", "test -race ./..." },
  { "Agent", "Agent ask", "ask" },
  { "Agent DDD", "Agent ddd fix", "fix" },
  { "Agent Tests", "Agent test write", "write" },
  { "Agent Lenses", "Agent lens security", "security" },
  { "Agent", "+Agent DDD", "+DDD" },
  { "Session", "Session restore session (this folder)", "restore (this folder)" },
  { "Comments", "Comments toggle comment under cursor", "toggle under cursor" },
  { "Find", "telescope find files", "files" },
  { "Find", "Find replace in project", "replace in project" },
  { "Harpoon", "Harpoon jump to file 2", "jump to file 2" },
  { "Dart / Flutter", "Dart format / organize", "format / organize" },
  { nil, "General save", "save" },
  { nil, "LSP code action", "code action" },
  { nil, "Find file history (session)", "Find file history (session)" },
  { "Go", "Go", "Go" },
}
for _, c in ipairs(LABELS) do
  check(labels.trim(c[1], c[2]) == c[3], ("labels: %s | %s -> %s (got %s)"):format(tostring(c[1]), c[2], c[3], labels.trim(c[1], c[2])))
end

-- a float painted as a soft block has to paint the rows past its last line (EndOfBuffer) and its sign column like the
-- block, or the window reads as a soft frame around a dark hole (the "thick border over the border" look)
for _, file in ipairs { "agent/ui/panel.lua", "agent/ui/float.lua", "agent/ui/inline.lua", "commit/panel.lua" } do
  local f = assert(io.open(root .. "/nvim/lua/" .. file, "r"))
  local src = f:read "*a"
  f:close()
  check(src:find("EndOfBuffer:Agent", 1, true) ~= nil, file .. ": EndOfBuffer follows the block")
  check(src:find("SignColumn:Agent", 1, true) ~= nil, file .. ": SignColumn follows the block")
end

print(fails == 0 and ("ALL OK (" .. total .. " checks)") or ("FAILURES: " .. fails .. " of " .. total))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
