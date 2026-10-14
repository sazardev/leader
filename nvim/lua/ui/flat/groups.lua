-- ── Flat design: highlight groups ────────────────────────────────────────────
-- Pure: tokens in, `{ group = attrs }` out (no Neovim state), so it can be tested and reused.
-- The rules, all of them from the landing page's demo editor:
--   · no borders and no radius: a surface is a filled block (`soft`) one step above the background;
--   · the border cells (`solid` = one blank cell of padding) are painted with the SAME color as the block;
--   · selection = solid blue with `on` text; matches = yellow; keys = yellow; groups = purple; hints = faint;
--   · additions/deletions/selections are VEILS of an accent over the background, never solid colors.
local palette = require "ui.flat.palette"

local M = {}

M.FRESH_STEPS = 6 -- frames of the "just changed" flash (FlatFresh1 … FlatFreshN, fading to nothing)

--- The inline agent: instruction block, running chip, proposed diff, answer window
---@param t FlatTokens
---@return table<string, table>
function M.agent(t)
  local function veil(c, a)
    return palette.veil(t, c, a)
  end
  return {
    AgentTarget = { bg = veil(t.fg, 0.05) }, -- the code that was sent, while it runs: a veil barely stronger than the background
    AgentStatus = { fg = t.purple, bg = veil(t.purple, 0.14), bold = true }, -- the spinner chip at the end of the line
    AgentDone = { fg = t.green, bg = veil(t.green, 0.12) },
    AgentHint = { fg = t.dim, italic = true }, -- it carries the accept/reject keys: it must stay readable
    AgentDiffAdd = { fg = t.fg, bg = veil(t.green, 0.16) },
    AgentDiffDelete = { bg = veil(t.red, 0.16) },
    AgentInput = { fg = t.fg, bg = t.soft },
    AgentInputBar = { fg = t.purple, bg = t.soft },
    AgentInputTitle = { fg = t.purple, bg = t.soft, bold = true },
    AgentInputMeta = { fg = t.faint, bg = t.soft },
    AgentInputHint = { fg = t.faint, bg = t.soft, italic = true },
    AgentInputPlaceholder = { fg = t.faint, bg = t.soft, italic = true },
    AgentFloat = { fg = t.fg, bg = t.soft },
    AgentBorder = { fg = t.soft, bg = t.soft },
    AgentTitle = { fg = t.faint, bg = t.soft, bold = true },
  }
end

--- The commit panel (<leader>G c): same surfaces as the agent, title bars like the demo
---@param t FlatTokens
---@return table<string, table>
function M.commit(t)
  local function veil(c, a)
    return palette.veil(t, c, a)
  end
  local bg = t.soft
  return {
    CommitOk = { fg = t.green, bg = bg, bold = true },
    CommitErr = { fg = t.red, bg = bg, bold = true },
    CommitWarn = { fg = t.yellow, bg = bg },
    CommitInfo = { fg = t.blue, bg = bg },
    CommitAdd = { fg = t.green, bg = bg },
    CommitDel = { fg = t.red, bg = bg },
    CommitChanged = { fg = t.blue, bg = bg },
    CommitStaged = { fg = t.green, bg = bg, bold = true },
    CommitUnstaged = { fg = t.dim, bg = bg },
    CommitDim = { fg = t.faint, bg = bg },
    CommitHeader = { fg = t.on, bg = t.blue, bold = true }, -- the title bars: solid blue with `on` text
    CommitAI = { fg = t.purple, bg = bg, bold = true },
    CommitCursor = { bg = veil(t.blue, 0.30) },
  }
end

---@param t FlatTokens
---@return table<string, table>
function M.build(t)
  local function veil(c, a)
    return palette.veil(t, c, a)
  end
  local block = { fg = t.fg, bg = t.soft }
  local pad = { fg = t.soft, bg = t.soft } -- the blank border cells: invisible, they only give air
  local selected = { fg = t.on, bg = t.blue, bold = true }
  local g = {}

  -- ── floats and native menus ───────────────────────────────────────────────
  g.NormalFloat = block
  g.FloatBorder = pad
  g.FloatTitle = { fg = t.faint, bg = t.soft, bold = true }
  g.FloatFooter = { fg = t.faint, bg = t.soft }
  g.Pmenu = { fg = t.dim, bg = t.soft }
  g.PmenuSel = selected
  g.PmenuSbar = { bg = t.soft }
  g.PmenuThumb = { bg = t.faint }
  g.PmenuBorder = pad
  g.PmenuKind = { fg = t.faint, bg = t.soft }
  g.PmenuKindSel = { fg = t.on, bg = t.blue }
  g.PmenuExtra = { fg = t.faint, bg = t.soft }
  g.PmenuExtraSel = { fg = t.on, bg = t.blue }
  g.PmenuMatch = { fg = t.yellow, bg = t.soft, bold = true }
  g.PmenuMatchSel = { fg = t.on, bg = t.blue, bold = true, underline = true }
  g.WinSeparator = { fg = t.soft, bg = "NONE" }
  g.VertSplit = g.WinSeparator

  -- ── completion (blink.cmp) and signature help ─────────────────────────────
  g.BlinkCmpMenu = { fg = t.dim, bg = t.soft }
  g.BlinkCmpMenuBorder = pad
  g.BlinkCmpMenuSelection = selected
  g.BlinkCmpScrollBarThumb = { bg = t.faint }
  g.BlinkCmpScrollBarGutter = { bg = t.soft }
  g.BlinkCmpLabel = { fg = t.dim }
  g.BlinkCmpLabelMatch = { fg = t.yellow, bold = true }
  g.BlinkCmpLabelDetail = { fg = t.faint }
  g.BlinkCmpLabelDescription = { fg = t.faint }
  g.BlinkCmpLabelDeprecated = { fg = t.faint, strikethrough = true }
  g.BlinkCmpSource = { fg = t.faint }
  g.BlinkCmpGhostText = { fg = t.faint, italic = true }
  g.BlinkCmpDoc = { fg = t.dim, bg = t.soft }
  g.BlinkCmpDocBorder = pad
  g.BlinkCmpDocSeparator = { fg = t.faint, bg = t.soft }
  g.BlinkCmpDocCursorLine = { bg = t.soft }
  g.BlinkCmpSignatureHelp = { fg = t.dim, bg = t.soft }
  g.BlinkCmpSignatureHelpBorder = pad
  g.BlinkCmpSignatureHelpActiveParameter = { fg = t.yellow, bg = t.soft, bold = true, underline = true }
  g.LspSignatureActiveParameter = g.BlinkCmpSignatureHelpActiveParameter

  -- ── which-key ─────────────────────────────────────────────────────────────
  g.WhichKey = { fg = t.yellow, bold = true }
  g.WhichKeyGroup = { fg = t.purple }
  g.WhichKeyDesc = { fg = t.dim }
  g.WhichKeySeparator = { fg = t.faint }
  g.WhichKeyNormal = block
  g.WhichKeyBorder = pad
  g.WhichKeyTitle = g.FloatTitle
  g.WhichKeyValue = { fg = t.faint }
  g.WhichKeyIcon = { fg = t.faint }

  -- ── telescope ─────────────────────────────────────────────────────────────
  -- three soft blocks (results, prompt, preview) over one `deep` frame: the border cells are the gaps between them
  local gap = { fg = t.deep, bg = t.deep }
  for _, part in ipairs { "Prompt", "Results", "Preview" } do
    g["Telescope" .. part .. "Normal"] = block
    g["Telescope" .. part .. "Border"] = gap
    g["Telescope" .. part .. "Title"] = { fg = t.faint, bg = t.deep, bold = true }
  end
  g.TelescopeNormal = block
  g.TelescopeBorder = gap
  g.TelescopeTitle = { fg = t.faint, bg = t.deep, bold = true }
  g.TelescopeResultsNormal = { fg = t.dim, bg = t.soft }
  g.TelescopePromptPrefix = { fg = t.fg, bg = t.soft }
  g.TelescopePromptCounter = { fg = t.faint, bg = t.soft }
  g.TelescopeSelection = selected
  g.TelescopeSelectionCaret = selected
  g.TelescopeMultiSelection = { fg = t.yellow, bg = t.soft, bold = true }
  g.TelescopeMatching = { fg = t.yellow, bold = true }
  g.TelescopeResultsComment = { fg = t.faint }

  -- ── file tree ─────────────────────────────────────────────────────────────
  g.NvimTreeNormal = { fg = t.fg, bg = t.deep }
  g.NvimTreeNormalNC = g.NvimTreeNormal
  g.NvimTreeEndOfBuffer = { fg = t.deep, bg = t.deep }
  g.NvimTreeWinSeparator = { fg = t.soft, bg = t.deep }
  g.NvimTreeCursorLine = { bg = t.soft }
  g.NvimTreeRootFolder = { fg = t.yellow, bold = true }
  g.NvimTreeFolderName = { fg = t.blue }
  g.NvimTreeOpenedFolderName = { fg = t.blue }
  g.NvimTreeEmptyFolderName = { fg = t.faint }
  g.NvimTreeIndentMarker = { fg = t.soft }
  g.NvimTreeBookmark = { fg = t.yellow }

  -- ── selection, search, cursor line ────────────────────────────────────────
  g.Visual = { bg = veil(t.blue, 0.30) }
  g.VisualNOS = g.Visual
  g.Search = { fg = t.fg, bg = veil(t.yellow, 0.30) }
  g.CurSearch = { fg = t.on, bg = t.yellow, bold = true }
  g.IncSearch = g.CurSearch
  g.MatchParen = { bg = veil(t.blue, 0.30), bold = true }
  g.LineNr = { fg = t.faint }
  g.CursorLineNr = { fg = t.yellow, bold = true }
  g.Folded = { fg = t.faint, italic = true }
  g.UfoFoldedEllipsis = { fg = t.faint }
  g.UfoFoldedFg = { fg = t.faint, italic = true }
  g.LspInlayHint = { fg = t.faint, italic = true }
  g.LspReferenceText = { bg = veil(t.fg, 0.08) }
  g.LspReferenceRead = g.LspReferenceText
  g.LspReferenceWrite = g.LspReferenceText
  g.IlluminatedWordText = g.LspReferenceText
  g.IlluminatedWordRead = g.LspReferenceText
  g.IlluminatedWordWrite = g.LspReferenceText
  g.IblIndent = { fg = veil(t.fg, 0.10) }
  g.IblScope = { fg = veil(t.fg, 0.24) }
  g.TreesitterContext = { bg = t.soft }
  g.TreesitterContextLineNumber = { fg = t.faint, bg = t.soft }
  g.TreesitterContextBottom = { sp = t.soft, underline = false }

  -- ── git: signs are thin bars; diff and conflicts are veils ────────────────
  g.GitSignsAdd = { fg = t.green }
  g.GitSignsChange = { fg = t.yellow }
  g.GitSignsDelete = { fg = t.red }
  g.DiffAdd = { bg = veil(t.green, 0.18) }
  g.DiffDelete = { fg = veil(t.red, 0.5), bg = veil(t.red, 0.18) }
  g.DiffChange = { bg = veil(t.yellow, 0.12) }
  g.DiffText = { bg = veil(t.yellow, 0.28) }
  g.DiffviewDiffAddAsDelete = { bg = veil(t.red, 0.18) }
  g.DiffviewDiffDelete = { fg = t.faint, bg = t.soft } -- filler rows: the empty counterpart of an added line
  g.DiffviewDiffDeleteDim = g.DiffviewDiffDelete
  g.DiffviewStatusAdded = { fg = t.green }
  g.DiffviewStatusModified = { fg = t.yellow }
  g.DiffviewStatusDeleted = { fg = t.red }
  g.DiffviewStatusRenamed = { fg = t.blue }
  g.GitConflictCurrent = { bg = veil(t.green, 0.14) }
  g.GitConflictIncoming = { bg = veil(t.blue, 0.14) }
  g.GitConflictAncestor = { bg = veil(t.yellow, 0.10) }
  g.GitConflictCurrentLabel = { fg = t.faint, bg = veil(t.green, 0.14), italic = true }
  g.GitConflictIncomingLabel = { fg = t.faint, bg = veil(t.blue, 0.14), italic = true }
  g.GitConflictAncestorLabel = { fg = t.faint, bg = veil(t.yellow, 0.10), italic = true }

  -- ── jumping and editing helpers ───────────────────────────────────────────
  g.FlashBackdrop = { fg = t.faint }
  g.FlashLabel = { fg = t.on, bg = t.purple, bold = true }
  g.FlashMatch = { fg = t.fg, bg = veil(t.blue, 0.38) }
  g.FlashCurrent = { fg = t.fg, bg = veil(t.blue, 0.38), bold = true }
  g.MultiCursorCursor = { fg = t.on, bg = t.purple }
  g.MultiCursorVisual = g.Visual
  g.MultiCursorDisabledCursor = { fg = t.on, bg = t.faint }
  g.MultiCursorDisabledVisual = { bg = veil(t.fg, 0.10) }

  -- ── project replace, diagnostics list ─────────────────────────────────────
  g.GrugFarInputLabel = { fg = t.aqua }
  g.GrugFarInputPlaceholder = { fg = t.faint, italic = true }
  g.GrugFarHelpHeader = { fg = t.faint }
  g.GrugFarResultsHeader = { fg = t.fg, bold = true }
  g.GrugFarResultsStats = { fg = t.faint }
  g.GrugFarResultsPath = { fg = t.blue }
  g.GrugFarResultsLineNr = { fg = t.faint }
  g.GrugFarResultsColumnNr = { fg = t.faint }
  g.GrugFarResultsMatch = { fg = t.red, bg = veil(t.red, 0.22) }
  g.GrugFarResultsMatchRemoved = { fg = t.red, bg = veil(t.red, 0.22), strikethrough = true }
  g.GrugFarResultsMatchAdded = { fg = t.green, bg = veil(t.green, 0.22) }
  g.TroubleNormal = block
  g.TroubleNormalNC = block
  g.TroubleText = { fg = t.dim }
  g.TroubleCount = { fg = t.faint, bg = t.soft }
  g.TroubleIndent = { fg = t.soft }
  g.TroubleSource = { fg = t.faint }
  g.TroublePos = { fg = t.faint }

  -- ── start screen ──────────────────────────────────────────────────────────
  g.NvDashAscii = { fg = t.aqua }
  g.NvDashFooter = { fg = t.yellow }
  g.NvDashButtons = { fg = t.dim, bg = t.soft }

  -- ── agent (<leader>a) and commit panel ───────────────────────────────────
  for name, def in pairs(M.agent(t)) do
    g[name] = def
  end
  for name, def in pairs(M.commit(t)) do
    g[name] = def
  end

  -- ── plugin managers: the same blocks, with solid chips for titles and the active tab ──
  g.LazyNormal = block
  g.LazyButton = { fg = t.dim, bg = veil(t.fg, 0.10) }
  g.LazyButtonActive = { fg = t.on, bg = t.yellow, bold = true }
  g.LazyH1 = { fg = t.on, bg = t.yellow, bold = true }
  g.LazyH2 = { fg = t.fg, bold = true }
  g.LazyProp = { fg = t.faint }
  g.LazyComment = { fg = t.faint }
  g.MasonNormal = block
  g.MasonHeader = { fg = t.on, bg = t.blue, bold = true }
  g.MasonHeaderSecondary = { fg = t.on, bg = t.blue }
  g.MasonHighlight = { fg = t.blue }
  g.MasonHighlightBlock = { fg = t.on, bg = t.green }
  g.MasonHighlightBlockBold = { fg = t.on, bg = t.green, bold = true }
  g.MasonHighlightBlockSecondary = { fg = t.on, bg = t.yellow }
  g.MasonHeading = { fg = t.fg, bold = true }
  g.MasonMuted = { fg = t.faint }
  g.MasonMutedBlock = { fg = t.dim, bg = veil(t.fg, 0.10) }

  -- ── notifications and the "just changed" flash ────────────────────────────
  g.FlatInput = { fg = t.fg, bg = t.deep } -- text fields inside a block (modal input)
  g.FlatNotify = block
  g.FlatNotifyTitle = { fg = t.fg, bg = t.soft, bold = true }
  g.FlatNotifyInfo = { fg = t.green, bg = t.soft }
  g.FlatNotifyWarn = { fg = t.yellow, bg = t.soft }
  g.FlatNotifyError = { fg = t.red, bg = t.soft }
  g.FlatNotifyDebug = { fg = t.faint, bg = t.soft }
  g.FlatKey = { fg = t.on, bg = t.fg, bold = true } -- the keycaps (ui/flat/keys.lua): solid, like the demo's
  g.FlatFresh = { bg = veil(t.yellow, 0.28) }
  for i = 1, M.FRESH_STEPS do
    -- frame 1 is the strongest, the last one is almost the background
    g["FlatFresh" .. i] = { bg = veil(t.yellow, 0.28 * (1 - (i - 1) / M.FRESH_STEPS)) }
  end

  return g
end

return M
