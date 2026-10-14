-- ── Start screen: layout ─────────────────────────────────────────────────────
-- Pure: window size + content in, lines and highlight spans out (no buffers, no Neovim state), so it is tested
-- headless. The design is the landing page's start screen: the art in aqua, the repo in yellow, the user faint,
-- then buttons of a fixed width (label left, shortcut right), a soft block each, the selected one solid blue.
-- It is responsive: when the window is short it drops the gaps between buttons, then the art, then centers what is left.
local M = {}

M.BUTTON_WIDTH = 38

---@class StartAction
---@field label string
---@field key string

---@class StartSpan
---@field row integer   0-based line
---@field col integer   0-based byte column
---@field end_col integer
---@field hl string

---@param text string
---@param width integer
---@return string
local function center(text, width)
  local pad = math.max(0, math.floor((width - vim.fn.strdisplaywidth(text)) / 2))
  return string.rep(" ", pad) .. text
end

--- Number of terminal rows the content needs
---@param art_rows integer
---@param n_buttons integer
---@param gaps boolean
---@param n_info integer
---@return integer
local function height_of(art_rows, n_buttons, gaps, n_info)
  local rows = n_buttons + (gaps and n_buttons - 1 or 0)
  if art_rows > 0 then
    rows = rows + art_rows + 1 -- the art and one blank row under it
  end
  if n_info > 0 then
    rows = rows + n_info + 1 -- repo / user and one blank row under them
  end
  return rows
end

---@param opts { width: integer, height: integer, art: string[], repo: string?, user: string?, actions: StartAction[], sel: integer }
---@return string[] lines, StartSpan[] spans, integer[] button_rows (0-based row of each button), boolean compact
function M.compute(opts)
  local w, h = opts.width, opts.height
  local actions = opts.actions
  local info = {}
  if opts.repo and opts.repo ~= "" then
    info[#info + 1] = { opts.repo, "NvStartRepo" }
  end
  if opts.user and opts.user ~= "" then
    info[#info + 1] = { opts.user, "NvStartUser" }
  end

  -- what fits: everything, then no gaps between buttons, then no art
  local art, gaps = opts.art or {}, true
  if height_of(#art, #actions, gaps, #info) > h - 1 then
    gaps = false
  end
  if height_of(#art, #actions, gaps, #info) > h - 1 then
    art = {}
  end
  local compact = not gaps
  local total = height_of(#art, #actions, gaps, #info)
  local top = math.max(0, math.floor((h - total) / 2) - 1) -- a touch above the center, like the web

  local lines, spans, rows = {}, {}, {}
  local function push(text, hl)
    lines[#lines + 1] = text
    if hl then
      spans[#spans + 1] = { row = #lines - 1, col = 0, end_col = #text, hl = hl }
    end
  end

  for _ = 1, top do
    push ""
  end
  if #art > 0 then
    local art_w = 0
    for _, l in ipairs(art) do
      art_w = math.max(art_w, vim.fn.strdisplaywidth(l))
    end
    local left = string.rep(" ", math.max(0, math.floor((w - art_w) / 2)))
    for _, l in ipairs(art) do
      lines[#lines + 1] = left .. l
      spans[#spans + 1] = { row = #lines - 1, col = #left, end_col = #left + #l, hl = "NvStartArt" }
    end
    push ""
  end
  for _, item in ipairs(info) do
    local text = center(item[1], w)
    lines[#lines + 1] = text
    spans[#spans + 1] = { row = #lines - 1, col = #text - #item[1], end_col = #text, hl = item[2] }
  end
  if #info > 0 then
    push ""
  end

  local bw = math.min(M.BUTTON_WIDTH, math.max(12, w - 2))
  local left = string.rep(" ", math.max(0, math.floor((w - bw) / 2)))
  for i, action in ipairs(actions) do
    local label, key = " " .. action.label, action.key .. " "
    local gap = math.max(1, bw - vim.fn.strdisplaywidth(label) - vim.fn.strdisplaywidth(key))
    local text = left .. label .. string.rep(" ", gap) .. key
    lines[#lines + 1] = text
    rows[i] = #lines - 1
    local selected = i == opts.sel
    local base, keyhl = selected and "NvStartSel" or "NvStartBtn", selected and "NvStartSelKey" or "NvStartBtnKey"
    spans[#spans + 1] = { row = #lines - 1, col = #left, end_col = #text, hl = base }
    spans[#spans + 1] = { row = #lines - 1, col = #text - #key, end_col = #text, hl = keyhl }
    if gaps and i < #actions then
      push ""
    end
  end
  return lines, spans, rows, compact
end

return M
