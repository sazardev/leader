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
  "FlashLabel", "MultiCursorCursor", "GrugFarResultsMatchRemoved", "FlatNotify", "FlatNotifyError", "FlatKey", "NvStartNormal", "NvStartSel", "NvStartBtn",
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
  check(g.TelescopePromptBorder.fg == t.deep, name .. ": telescope gaps use the `deep` frame")

  -- readability: selection text over the blue, keys and matches over the block, hints over the block
  check(color.contrast(t.on, t.blue) >= 3.0, name .. ": selected text unreadable (" .. color.contrast(t.on, t.blue) .. ")")
  check(color.contrast(t.yellow, t.soft) >= 2.5, name .. ": yellow keys unreadable over the block")
  check(color.contrast(t.dim, t.soft) >= 3.5, name .. ": dim text unreadable over the block")
  check(color.contrast(t.faint, t.soft) >= 1.9, name .. ": faint hints vanish over the block")

  -- the "just changed" flash fades: each frame is closer to the background than the one before
  local function distance(i)
    local bg = g["FlatFresh" .. i].bg
    return math.abs(color.luminance(bg) - color.luminance(t.bg))
  end
  for i = 2, groups.FRESH_STEPS do
    check(distance(i) < distance(i - 1) + 1e-9, name .. ": flash frame " .. i .. " does not fade")
  end

  -- added / removed lines are veils (close to the background), never solid colors
  check(color.contrast(g.DiffAdd.bg, t.bg) < 1.6, name .. ": DiffAdd must be a veil")
  -- (the theme's own text contrast is its business: the veil may only cost a little of it)
  check(color.contrast(t.fg, g.DiffAdd.bg) >= math.min(4.5, 0.7 * color.contrast(t.fg, t.bg)), name .. ": text over DiffAdd unreadable")
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

print(fails == 0 and ("ALL OK (" .. total .. " checks)") or ("FAILURES: " .. fails .. " of " .. total))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
