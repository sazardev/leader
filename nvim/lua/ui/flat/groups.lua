-- ── Flat design: highlight groups ────────────────────────────────────────────
-- Pure: tokens in, `{ group = attrs }` out (no Neovim state), so it can be tested and reused.
-- The rules, all of them from the landing page's demo editor:
--   · no borders and no radius: a surface is a filled block (`soft`) one step above the background;
--   · the border cells (`solid` = one blank cell of padding) are painted with the SAME color as the block;
--   · selection = solid blue with `on` text; matches = yellow; keys = yellow; groups = purple; hints = faint;
--   · additions/deletions/selections are VEILS of an accent over the background, never solid colors.
local color = require "appearance.color"
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
    CommitHeaderWarn = { fg = t.on, bg = t.yellow, bold = true }, -- the subject is getting long
    CommitHint = { fg = t.faint, bg = bg, italic = true }, -- the key hints under each block
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
  -- half-block edges (`▄`/`▀`/`▌`): one half is the block, the other the editor behind it. A cell is ~19px tall,
  -- the demo's paddings and gaps are 2-8px: half a cell is the closest a terminal gets
  local edge = { fg = t.soft, bg = t.deep }
  local selected = { fg = t.on, bg = t.blue }
  local g = {}

  -- ── the editor surface: `deep`, like the demo's editor (the theme's own bg is the page around it) ──
  g.Normal = { fg = t.fg, bg = t.deep }
  g.NormalNC = g.Normal
  g.SignColumn = { bg = t.deep }
  g.FoldColumn = { fg = t.faint, bg = t.deep }
  g.EndOfBuffer = { fg = t.deep, bg = t.deep }
  g.FlatEdge = edge
  g.FlatGap = { fg = t.deep, bg = t.deep } -- a cell of editor inside a float (the gap under the message block)
  -- the command line and Neovim's own messages: on the editor surface; the separator above a dialog or the pager is
  -- part of its block, not a gray rule
  g.MsgArea = { fg = t.fg, bg = t.deep }
  g.MsgSeparator = { fg = t.soft, bg = t.soft }

  -- ── floats and native menus ───────────────────────────────────────────────
  g.NormalFloat = block
  g.FloatBorder = pad
  g.FloatTitle = { fg = t.faint, bg = t.soft, bold = true }
  g.FloatFooter = { fg = t.faint, bg = t.soft }
  g.FlatFloatHeader = { fg = t.fg, bg = t.soft, bold = true } -- `Diagnostics:` atop the line popup
  g.FlatFloatSource = { fg = t.faint, bg = t.soft }
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
  g.WhichKeyEdge = edge
  g.WhichKeyPressed = { fg = t.on, bg = t.yellow }
  g.WhichKeyTitle = g.FloatTitle
  g.WhichKeyValue = { fg = t.faint }
  g.WhichKeyIcon = { fg = t.faint }

  -- ── telescope ─────────────────────────────────────────────────────────────
  -- three soft blocks (results, prompt, preview) with half-cell gaps of editor between them (ui/flat/telescope.lua);
  -- each title is the block's first row, in faint capitals: inside the block, not on a border
  for _, part in ipairs { "Prompt", "Results", "Preview" } do
    g["Telescope" .. part .. "Normal"] = block
    g["Telescope" .. part .. "Border"] = pad
    g["Telescope" .. part .. "Title"] = { fg = t.faint, bg = t.soft, bold = true }
  end
  g.TelescopeNormal = block
  g.TelescopeBorder = pad
  g.TelescopeTitle = { fg = t.faint, bg = t.soft, bold = true }
  g.TelescopeResultsNormal = { fg = t.dim, bg = t.soft }
  g.TelescopePromptPrefix = { fg = t.fg, bg = t.soft }
  g.TelescopePromptCounter = { fg = t.faint, bg = t.soft }
  g.TelescopeSelection = selected
  g.TelescopeSelectionCaret = selected
  g.TelescopeMultiSelection = { fg = t.yellow, bg = t.soft, bold = true }
  g.TelescopeMatching = { fg = t.yellow, bold = true }
  g.TelescopeResultsComment = { fg = t.faint }
  -- grep rows: `path:line:col:` faint, the text dim
  g.TelescopeResultsIdentifier = { fg = t.faint }
  g.TelescopeResultsLineNr = { fg = t.faint }
  g.TelescopeResultsColumnNr = { fg = t.faint }
  g.TelescopePreviewPath = { fg = t.yellow, bg = t.soft } -- the file the preview shows, above its code
  g.TelescopePreviewLineNr = { fg = t.faint, bg = t.soft }
  -- the hit in the preview: a soft yellow veil (the demo's), never the blue selection over faint text
  g.TelescopePreviewLine = { bg = veil(t.yellow, 0.18) }
  g.TelescopePreviewMatch = { fg = t.yellow, bold = true }

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
  -- what starts with a dot (shown with `H` in the tree): purple, so it reads as "not part of the project proper" at a glance
  local hidden = color.ensure_contrast(t.purple, t.deep, t.fg, 3.0)
  g.NvimTreeHiddenFileHL = { fg = hidden }
  g.NvimTreeHiddenFolderHL = { fg = hidden }
  g.NvimTreeIndentMarker = { fg = t.deep }
  g.NvimTreeBookmark = { fg = t.yellow }
  g.NvimTreeBookmarkIcon = { fg = t.yellow }
  -- every file reads the same, like the demo's tree: no special/executable/image colors
  g.NvimTreeSpecialFile = { fg = t.fg }
  g.NvimTreeExecFile = { fg = t.fg }
  g.NvimTreeImageFile = { fg = t.fg }
  g.NvimTreeSymlink = { fg = t.fg }
  g.NvimTreeFileName = { fg = t.fg }

  -- ── selection, search, cursor line ────────────────────────────────────────
  g.Visual = { bg = t.selection or veil(t.blue, 0.30) } -- the terminal theme keeps the terminal's own selection
  g.VisualNOS = g.Visual
  g.Search = { fg = t.fg, bg = veil(t.yellow, 0.30) }
  g.CurSearch = { fg = t.on, bg = t.yellow, bold = true }
  g.IncSearch = g.CurSearch
  g.MatchParen = { bg = veil(t.blue, 0.30), bold = true }
  -- text is never chipped: base46 paints TODO/NOTE and quotes on a background of their own, a patch on any float
  g.Todo = { fg = t.yellow, bold = true }
  g["@comment.todo"] = g.Todo
  g["@comment.note"] = { fg = t.blue, bold = true }
  g["@comment.warning"] = { fg = t.orange, bold = true }
  g["@comment.danger"] = { fg = t.red, bold = true }
  g["@markup.quote"] = { fg = t.dim }
  -- markdown tables (render-markdown): flat columns, the heading row bold
  g.RenderMarkdownTableHead = { fg = t.faint, bold = true }
  g.RenderMarkdownTableRow = { fg = t.faint }
  -- the list bullet takes the color of the block it sits in (its default group is `Normal`: a dark square on any float)
  g.RenderMarkdownBullet = { fg = t.faint }
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
  -- the file panel is a soft block like the demo's; its root path row stays as air on top
  g.DiffviewNormal = { fg = t.dim, bg = t.soft }
  g.DiffviewEndOfBuffer = { fg = t.soft, bg = t.soft }
  g.DiffviewWinSeparator = { fg = t.soft, bg = t.deep }
  g.DiffviewCursorLine = { fg = t.on, bg = t.blue }
  g.DiffviewFilePanelRootPath = { fg = t.soft, bg = t.soft }
  g.DiffviewFilePanelTitle = { fg = t.faint, bg = t.soft, bold = true }
  g.DiffviewFilePanelCounter = { fg = t.faint, bg = t.soft }
  g.DiffviewFilePanelFileName = { fg = t.dim, bg = t.soft }
  g.DiffviewFilePanelPath = { fg = t.faint, bg = t.soft }
  g.DiffviewFilePanelInsertions = { fg = t.green, bg = t.soft }
  g.DiffviewFilePanelDeletions = { fg = t.red, bg = t.soft }
  g.DiffviewPaneTitle = { fg = t.faint, bg = t.deep, bold = true } -- HEAD / WORKING TREE
  g.DiffviewStatusAdded = { fg = t.green }
  g.DiffviewStatusModified = { fg = t.yellow, bold = true }
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
  -- grug-far is a soft panel; each input is a `deep` bar with its aqua label inside (ui/flat/grug.lua)
  g.GrugFarNormal = block
  g.GrugFarInput = { fg = t.fg, bg = t.deep }
  g.GrugFarInputLabel = { fg = t.aqua, bg = t.deep }
  g.GrugFarInputPlaceholder = { fg = t.deep, bg = t.deep } -- an empty compact input repeats its label: hidden (ours is shown)
  g.GrugFarHeader = { fg = t.fg, bg = t.soft, bold = true }
  g.GrugFarHelpHeader = { fg = t.faint }
  g.GrugFarResultsHeader = { fg = t.fg, bold = true }
  g.GrugFarResultsStats = { fg = t.faint }
  g.GrugFarResultsActionMessage = { fg = t.faint }
  g.GrugFarResultsPath = { fg = t.blue }
  g.GrugFarResultsLineNr = { fg = t.faint }
  g.GrugFarResultsColumnNr = { fg = t.faint }
  g.GrugFarResultsMatch = { fg = t.red, bg = veil(t.red, 0.22), strikethrough = true } -- what would go: the demo strikes it
  g.GrugFarResultsMatchRemoved = { fg = t.red, bg = veil(t.red, 0.22), strikethrough = true }
  g.GrugFarResultsMatchAdded = { fg = t.green, bg = veil(t.green, 0.22) }
  g.TroubleNormal = block
  g.TroubleNormalNC = block
  g.TroubleCursorLine = { bg = t.deep }
  g.TroubleTitle = { fg = t.fg, bg = t.soft, bold = true }
  g.TroubleText = { fg = t.dim }
  g.TroubleCount = { fg = t.faint, bg = t.soft }
  g.TroubleIndent = { fg = t.soft }
  g.TroubleSource = { fg = t.faint }
  g.TroublePos = { fg = t.faint }

  -- ── start screen ──────────────────────────────────────────────────────────
  g.NvStartNormal = { fg = t.fg, bg = t.deep } -- the editor surface, like the demo's start screen
  g.NvStartArt = { fg = t.aqua }
  g.NvStartRepo = { fg = t.yellow }
  g.NvStartUser = { fg = t.faint }
  g.NvStartBtn = { fg = t.dim, bg = t.soft }
  g.NvStartBtnKey = { fg = t.faint, bg = t.soft }
  g.NvStartSel = { fg = t.on, bg = t.blue }
  g.NvStartSelKey = { fg = t.on, bg = t.blue }
  g.NvStartEdge = { fg = t.soft, bg = t.deep } -- the lower half of a button (`▀`): the other half is the gap
  g.NvStartSelEdge = { fg = t.blue, bg = t.deep }
  g.NvStartCursor = { blend = 100, nocombine = true } -- hides the cursor while the start screen is shown

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

  -- ── modals (utils/modal.lua, harpoon): a soft block, title in capitals, input on a `deep` bar ──
  -- text fields inside a block (modal input): one step darker than the block, halfway to `deep`. On a terminal theme `deep`
  -- is nearly black, and a bar of it inside the block reads as a hole
  g.FlatInput = { fg = t.fg, bg = color.blend(t.soft, t.deep, 0.5) }
  g.FlatModalTitle = { fg = t.fg, bg = t.soft, bold = true }
  g.FlatModalHint = { fg = t.faint, bg = t.soft }
  g.FlatModalRow = { bg = t.soft } -- under every modal row: the block's color, nothing else (the text keeps its own)
  g.FlatModalSel = selected -- the chosen row: a chip as wide as its text
  -- buttons under a modal (utils/modal.lua): small chips. Primary = blue like the chosen row, soft = a step over the block,
  -- danger = red for what cannot be taken back
  g.FlatButton = { fg = t.on, bg = t.blue, bold = true }
  g.FlatButtonSoft = { fg = t.fg, bg = color.blend(t.soft, t.fg, 0.12) }
  g.FlatButtonDanger = { fg = t.on, bg = t.red, bold = true }
  g.FlatFolder = { fg = t.blue, bg = t.soft }
  g.FlatMark = { fg = t.yellow, bg = t.soft }
  g.FlatWarn = { fg = t.yellow, bg = t.soft }
  -- the terminal float: the theme's own background (one step over the `deep` editor, like the demo's)
  g.FlatTerm = { fg = t.fg, bg = t.bg }
  g.FlatTermBorder = { fg = t.bg, bg = t.bg }

  -- ── notifications and the "just changed" flash ────────────────────────────
  g.FlatNotify = block
  g.FlatNotifyTitle = { fg = t.fg, bg = t.soft, bold = true }
  g.FlatNotifyInfo = { fg = t.green, bg = t.soft }
  g.FlatNotifyWarn = { fg = t.yellow, bg = t.soft }
  g.FlatNotifyError = { fg = t.red, bg = t.soft }
  g.FlatNotifyDebug = { fg = t.faint, bg = t.soft }
  -- the leading phrase of a note, bold in its level's color
  g.FlatNotifyInfoLead = { fg = t.green, bg = t.soft, bold = true }
  g.FlatNotifyWarnLead = { fg = t.yellow, bg = t.soft, bold = true }
  g.FlatNotifyErrorLead = { fg = t.red, bg = t.soft, bold = true }
  g.FlatNotifyDebugLead = { fg = t.dim, bg = t.soft, bold = true }
  g.FlatKey = { fg = t.on, bg = t.fg, bold = true } -- the keycaps (ui/flat/keys.lua): solid, like the demo's
  g.FlatFresh = { bg = veil(t.yellow, 0.28) }
  for i = 1, M.FRESH_STEPS do
    -- frame 1 is the strongest, the last one is almost the background
    g["FlatFresh" .. i] = { bg = veil(t.yellow, 0.28 * (1 - (i - 1) / M.FRESH_STEPS)) }
  end

  return g
end

--- Moves every group painted with the theme's background onto the editor surface (`deep`): base46 and plugins
--- paint dozens of groups with the theme bg (gutter, statusline parts, plugin windows); they must follow the editor.
--- `fg` equal to the old bg is moved too: it is how themes hide a character (end of buffer, separators).
--- Pure: `all` is what `nvim_get_hl(0, {})` returns, `skip` the groups `build` already defined.
---@param all table<string, table>
---@param old integer theme background as a number
---@param new integer
---@param skip table<string, any>
---@return table<string, table> changed groups (full definitions, ready for nvim_set_hl)
function M.rebase(all, old, new, skip)
  local out = {}
  for name, def in pairs(all) do
    if not skip[name] and not def.link and (def.bg == old or def.fg == old) then
      local d = vim.deepcopy(def)
      if d.bg == old then
        d.bg = new
      end
      if d.fg == old then
        d.fg = new
      end
      out[name] = d
    end
  end
  return out
end

return M
