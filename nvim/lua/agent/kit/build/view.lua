-- ── Build with agent: the view ───────────────────────────────────────────────
-- A tab that draws build/state.lua, so it can be closed and opened again at any moment (the build goes on without it):
--   left    the phases as chips (plan review write check fix use done), the progress bar, then what the phase needs: models
--           and documents (ready), the estimate (review), the files with their lines and cost (the one being written on
--           a full-width band, like the agent's inline target) and the checks
--   code    the file being written, typed out as it arrives (`c` hides it: only the list advancing)
--   feed    what every request carried (→) and what it cost (←) (`f` hides it)
--   status  the statusline (a lualine extension): the phase as the mode chip, the keys of the moment, then
--           progress · money · cache · time
-- Buffers are kept (hidden, never wiped) and the layout is rebuilt from them: closing a pane, opening a file in the code
-- pane or closing the tab never breaks the build. Colors come from the flat design groups (chips = FlatButton/Soft).
require("agent.ui.highlights").ensure()

local state = require "agent.kit.build.state"

local M = {}

local NS = vim.api.nvim_create_namespace "AgentKitBuild"
local SPIN = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local STEPS = { "plan", "review", "write", "check", "fix", "use", "done" }
local LEFT_W = 50

local LINKS = {
  KitBuildTitle = "AgentTitle",
  KitBuildDone = "AgentDone",
  KitBuildActive = "FlatMark",
  KitBuildPending = "Comment",
  KitBuildFail = "DiagnosticError",
  KitBuildMuted = "Comment",
  KitBuildPath = "FlatFolder",
  KitBuildKey = "FlatMark",
  KitBuildMoney = "AgentDone",
  KitBuildBarFill = "FlatMark",
  KitBuildBarEmpty = "FlatEdge",
}

--- Chips and statusline groups, derived from the flat design and the statusline's own background
local function highlights()
  for name, link in pairs(LINKS) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
  local function hl(name)
    return vim.api.nvim_get_hl(0, { name = name, link = false })
  end
  local soft = hl("FlatButtonSoft").bg or hl("CursorLine").bg
  local primary = hl "FlatButton"
  local status = hl("StatusLine").bg
  local done_fg, faint, mark = hl("AgentDone").fg, hl("Comment").fg, hl("FlatMark").fg or hl("DiagnosticWarn").fg
  -- faint text without Comment's italics (the theme may slant comments): every label in the view reads the same
  vim.api.nvim_set_hl(0, "KitBuildMuted", { fg = faint })
  vim.api.nvim_set_hl(0, "KitBuildPending", { fg = faint })
  vim.api.nvim_set_hl(0, "KitBuildChipNow", { fg = primary.fg, bg = primary.bg, bold = true })
  vim.api.nvim_set_hl(0, "KitBuildChipDone", { fg = done_fg, bg = soft })
  vim.api.nvim_set_hl(0, "KitBuildChipNext", { fg = faint, bg = soft })
  vim.api.nvim_set_hl(0, "KitBuildChipFail", { link = "FlatButtonDanger" })
  vim.api.nvim_set_hl(0, "KitBuildRow", { link = "AgentTarget" })
  -- the statusline's phase chip, colored by how the run stands
  local on = primary.fg
  local function chip(bg_from)
    return { fg = on, bg = hl(bg_from).fg, bold = true }
  end
  vim.api.nvim_set_hl(0, "KitBuildStateRun", { fg = primary.fg, bg = primary.bg, bold = true })
  vim.api.nvim_set_hl(0, "KitBuildStateOk", chip "DiagnosticOk")
  vim.api.nvim_set_hl(0, "KitBuildStateWarn", chip "DiagnosticWarn")
  vim.api.nvim_set_hl(0, "KitBuildStateFail", chip "DiagnosticError")
  vim.api.nvim_set_hl(0, "KitBuildSl", { fg = faint, bg = status })
  vim.api.nvim_set_hl(0, "KitBuildSlKey", { fg = mark, bg = status, bold = true })
  vim.api.nvim_set_hl(0, "KitBuildSlMoney", { fg = done_fg, bg = status, bold = true })
end

local V = {
  tab = nil, ---@type integer?
  -- buffers (kept for the session)
  left = nil, ---@type integer?
  code = nil, ---@type integer?
  feed = nil, ---@type integer?
  -- windows (rebuilt by layout())
  wl = nil, ---@type integer?
  wc = nil, ---@type integer?
  wf = nil, ---@type integer?
  -- what is shown (c, f)
  show_code = true,
  show_feed = true,
  show_left = true,
  zoom = false, -- z: only the code pane, full screen, the cursor in it
  rows = {}, ---@type table<integer, string> left row → file path
  bands = {}, ---@type table<integer, string> left row → full-width band group
  frame = 0,
  timer = nil, ---@type uv.uv_timer_t?
  typing = nil, ---@type uv.uv_timer_t?
  text = "",
  current = nil, ---@type string?
  streamed = false,
  pending_draw = false,
}

---@param win integer?
---@return boolean
local function win_ok(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

---@param buf integer?
---@return boolean
local function buf_ok(buf)
  return buf ~= nil and vim.api.nvim_buf_is_valid(buf)
end

---@return boolean
local function shown()
  return V.tab ~= nil and vim.api.nvim_tabpage_is_valid(V.tab)
end

---@param name string
---@return integer
local function scratch(name)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  pcall(vim.api.nvim_buf_set_name, buf, name)
  return buf
end

---@param n integer
---@return string
local function size(n)
  return n >= 1000 and ("%.1fk"):format(n / 1000) or tostring(n)
end

---@param s string
---@return integer
local function width(s)
  return vim.fn.strdisplaywidth(s)
end

---@param win integer?
---@param text string?
local function winbar(win, text)
  if win_ok(win) then
    vim.wo[win].winbar = text and ("%#KitBuildMuted# " .. text:gsub("%%", "%%%%")) or ""
  end
end

---@param lines string[]
---@param marks table
---@param text string
---@param hls { [1]: integer, [2]: integer, [3]: string }[]?
local function add(lines, marks, text, hls)
  lines[#lines + 1] = text
  marks[#lines] = hls
end

---@param buf integer?
---@param lines string[]
---@param marks table
---@param bands table<integer, string>?
local function paint(buf, lines, marks, bands)
  if not buf_ok(buf) then
    return
  end
  for i, l in ipairs(lines) do
    if l:find("\n", 1, true) then -- a line must not carry a newline (set_lines refuses it)
      lines[i] = l:gsub("\n", " ")
    end
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  for row, hls in pairs(marks) do
    for _, h in ipairs(hls or {}) do
      if h[3] then
        pcall(vim.api.nvim_buf_set_extmark, buf, NS, row - 1, h[1], { end_col = h[2], hl_group = h[3], strict = false })
      end
    end
  end
  for row, group in pairs(bands or {}) do -- a whole row painted (the file being written), under the text's own colors
    pcall(vim.api.nvim_buf_set_extmark, buf, NS, row - 1, 0, { line_hl_group = group, priority = 50 })
  end
end

-- ── Phases (chips) and the statusline ────────────────────────────────────────

---@param run BuildRun
---@return string
local function at(run)
  if vim.tbl_contains(STEPS, run.phase) then
    return run.phase
  end
  return run.phase == "ready" and "ready" or (run.at or "write")
end

--- The phases as a row of chips: done, now (with the spinner while it works), next; a failed run's phase in red
---@param run BuildRun
---@return string text, table hls
local function chips(run)
  local now = at(run)
  local idx = 0
  for i, s in ipairs(STEPS) do
    if s == now then
      idx = i
    end
  end
  local text, hls = "  ", {}
  for i, s in ipairs(STEPS) do
    local label = s
    if i == idx and run.running then
      label = SPIN[V.frame % #SPIN + 1] .. " " .. s
    end
    local chip = " " .. label .. " "
    local group = (run.phase == "done" or i < idx) and "KitBuildChipDone"
      or (i == idx and (run.phase == "failed" and "KitBuildChipFail" or "KitBuildChipNow"))
      or "KitBuildChipNext"
    hls[#hls + 1] = { #text, #text + #chip, group }
    text = text .. chip .. " "
  end
  return text, hls
end

--- The keys of the moment: { key, what }
---@param run BuildRun
---@return { [1]: string, [2]: string }[]
local function keys_now(run)
  local view = V.zoom and { { "z", "back" } }
    or { { "z", "focus" }, { "P", "plan" }, { "⇥", "pane" }, { "l", "files" }, { "c", "code" }, { "f", "feed" } }
  local list
  if run.running then
    list = { { "x", "stop" }, { "p", "prompt" } }
  elseif run.phase == "ready" then
    list = { { "⏎", "plan" }, { "1-4", "tiers" } }
  elseif run.phase == "review" then
    list = { { "⏎", "build" }, { "x", "skip" }, { "n", "replan" }, { "X", "clean" } }
  elseif run.phase == "done" then
    list = { { "⏎", "open" }, { "r", "recheck" }, { "n", "replan" }, { "X", "clean" } }
  else
    list = { { "⏎", "resume" }, { "r", "recheck" }, { "n", "replan" }, { "X", "clean" } }
  end
  list[#list + 1] = { "q", run.running and "hide" or "close" }
  vim.list_extend(list, view)
  return list
end

-- The build tab's statusline is a lualine extension (ui/lualine/components.lua `build_extension`, filetype agentbuild):
-- the phase in the mode chip, the keys of the moment, then progress · money · cache · time

--- The phase, for the mode chip ("write", "done", "failed"…)
---@return string
function M.status_phase()
  local run = state.run
  if not run then
    return ""
  end
  if run.phase == "done" or run.phase == "failed" or run.phase == "stopped" then
    return (run.outcome and run.outcome:find "^✗") and "failed" or run.phase
  end
  return (run.running and (SPIN[V.frame % #SPIN + 1] .. " ") or "") .. at(run)
end

--- The chip's color: failed red, stopped or paused yellow, done green, working or ready the primary chip
---@return string
function M.status_color()
  local run = state.run
  local phase = M.status_phase()
  if phase == "failed" then
    return "KitBuildStateFail"
  elseif run and run.phase == "done" then
    return "KitBuildStateOk"
  elseif run and (run.phase == "stopped" or (run.outcome and not run.running and run.phase ~= "ready")) then
    return "KitBuildStateWarn"
  end
  return "KitBuildStateRun"
end

--- What the figures take at this width: "7/23 · $0.031 · 61% cached · 2m10s", then shorter as the screen narrows
---@param room integer
---@return string
local function figures(room)
  local run = state.run --[[@as BuildRun]]
  local done, total = state.progress()
  local t = run.totals
  local secs = require("agent.kit.build").elapsed()
  local cached = t.tokens_in > 0 and math.floor(100 * t.cached / t.tokens_in + 0.5) or 0
  local parts = {}
  if total > 0 and run.phase ~= "review" and run.phase ~= "ready" then
    parts[#parts + 1] = ("%d/%d"):format(done, total)
  end
  parts[#parts + 1] = ("$%.3f"):format(t.cost)
  local full = vim.list_extend(
    vim.deepcopy(parts),
    { ("%d%% cached"):format(cached), ("%dm%02ds"):format(math.floor(secs / 60), secs % 60) }
  )
  local text = table.concat(full, " · ")
  if width(text) > room then
    text = table.concat(parts, " · ")
  end
  return text
end

--- "7/23 · $0.031 · 61% cached · 2m10s" (shorter when the screen is narrow)
---@return string
function M.status_figures()
  if not state.run then
    return ""
  end
  local room = math.max(12, math.floor(vim.o.columns * 0.3))
  return (figures(room):gsub("%%", "%%%%")) -- a statusline reads a lone % as an item
end

--- The keys of the moment, most useful first, as many as fit beside the chip and the figures
---@return string
function M.status_keys()
  local run = state.run
  if not run then
    return ""
  end
  local room = vim.o.columns - 14 - width(figures(math.max(12, math.floor(vim.o.columns * 0.3)))) - 6
  local out, used = {}, 0
  for _, k in ipairs(keys_now(run)) do
    local item = k[1] .. " " .. k[2]
    local cost = width(item) + (#out > 0 and 3 or 0)
    if used + cost > room then
      break
    end
    out[#out + 1] = item
    used = used + cost
  end
  return (table.concat(out, "   "):gsub("%%", "%%%%"))
end

-- ── Left: what the phase needs, the files, the checks, the keys ──────────────

---@param run BuildRun
---@return string[], table
local function left(run)
  local lines, marks = {}, {}
  V.rows, V.bands = {}, {}
  local spin = SPIN[V.frame % #SPIN + 1]
  local build = require "agent.kit.build"
  local inner = LEFT_W
  if not (V.show_code or V.show_feed) and win_ok(V.wl) then
    inner = math.max(LEFT_W, math.min(100, vim.api.nvim_win_get_width(V.wl) - 4))
  end
  add(lines, marks, "")
  local chip_text, chip_hls = chips(run)
  add(lines, marks, chip_text, chip_hls)
  add(lines, marks, "")

  -- progress (from write on), or how it ended
  local done, total = state.progress()
  if run.outcome and not run.running then
    local hl = run.outcome:find "^✓" and "KitBuildDone"
      or run.outcome:find "^✗" and "KitBuildFail"
      or "KitBuildActive"
    add(lines, marks, "  " .. run.outcome, { { 2, 2 + #run.outcome, hl } })
    add(lines, marks, "")
  elseif total > 0 and run.phase ~= "review" and run.phase ~= "ready" then
    local bar_w = inner - 10
    local fill = math.floor(bar_w * done / total + 0.5)
    local filled, empty = ("━"):rep(fill), ("━"):rep(bar_w - fill)
    local row = "  " .. filled .. empty .. ("  %d/%d"):format(done, total)
    add(lines, marks, row, {
      { 2, 2 + #filled, "KitBuildBarFill" },
      { 2 + #filled, 2 + #filled + #empty, "KitBuildBarEmpty" },
      { 2 + #filled + #empty, #row, "KitBuildMuted" },
    })
    add(lines, marks, "")
  end

  local function heading(text)
    add(lines, marks, "  " .. text, { { 2, 2 + #text, "KitBuildMuted" } })
  end

  -- models: only while they can still change (before it writes)
  if not run.running and (run.phase == "ready" or run.phase == "review") then
    heading "MODELS"
    for i, phase in ipairs(build.TIERED) do
      local label = build.model(phase)
      local tier = run.tiers[phase] or "main"
      local row = ("  %d %-6s %-24s %s"):format(i, phase, label, tier)
      add(lines, marks, row, {
        { 2, 3, "KitBuildKey" },
        { 4, 10, "KitBuildMuted" },
        { 11, 11 + #label, "KitBuildTitle" },
        { #row - #tier, #row, "KitBuildMuted" },
      })
    end
    local fixes = ("  ± rounds without progress  %d"):format(run.max_fixes)
    add(lines, marks, fixes, { { 2, 4, "KitBuildKey" }, { 5, #fixes, "KitBuildMuted" } })
    add(lines, marks, "")
  end

  if run.phase == "ready" then
    heading "DOCUMENTS"
    for _, d in ipairs(run.docs) do
      local row = ("  ● %-12s %6s"):format(d.file, size(d.chars))
      add(lines, marks, row, { { 2, 5, "KitBuildDone" }, { 5, 18, "KitBuildPath" }, { 18, #row, "KitBuildMuted" } })
    end
    add(lines, marks, "")
    local est = build.plan_estimate()
    local note = ("  plan · 1 request · ~%s in%s"):format(
      size(est.tokens),
      est.cost and (" · ~$%.3f"):format(est.cost) or ""
    )
    add(lines, marks, note, { { 2, #note, "KitBuildMoney" } })
    add(lines, marks, "")
  end

  if run.phase == "review" and run.estimate then
    local e = run.estimate
    local cost = e.cost and ("~$%.3f"):format(e.cost) or "no price yet"
    local row = ("  %d files · ~%s in · %s"):format(e.files or 0, size(e.tokens), cost)
    add(lines, marks, row, { { 2, #row, "KitBuildMoney" } })
    if e.nocache then
      local r1 = ("  ~$%.3f without the cache"):format(e.nocache)
      add(lines, marks, r1, { { 2, #r1, "KitBuildMuted" } })
    end
    if (run.replaced or 0) > 0 then
      local r2 = ("  replaces %d file%s · old ones to the trash"):format(run.replaced, run.replaced == 1 and "" or "s")
      add(lines, marks, r2, { { 2, #r2, "KitBuildActive" } })
    end
    if run.stale and #run.stale > 0 then
      local r3 = ("  %d leftover%s of the last build to the trash"):format(#run.stale, #run.stale == 1 and "" or "s")
      add(lines, marks, r3, { { 2, #r3, "KitBuildActive" } })
    end
    add(lines, marks, "")
  end

  if #run.files > 0 then
    heading "FILES"
    for _, f in ipairs(run.files) do
      local mark = ({
        pending = { "○", "KitBuildPending" },
        writing = { spin, "KitBuildActive" },
        done = { "●", "KitBuildDone" },
        fixed = { "●", "KitBuildActive" },
        failed = { "✗", "KitBuildFail" },
        skipped = { "–", "KitBuildPending" },
      })[f.state] or { "○", "KitBuildPending" }
      local right = ""
      if f.lines then
        right = ("%5d  %s"):format(f.lines, f.cost and (("$%.4f"):format(f.cost):gsub("^%$0", "$")) or "")
      elseif run.phase == "review" and f.estimate and f.state ~= "skipped" then
        right = ("~%s"):format(size(f.estimate))
      end
      local room = inner - 6 - width(right)
      local path = f.path
      if width(path) > room then
        path = "…" .. path:sub(-(room - 1))
      end
      local row = ("  %s %s"):format(mark[1], path)
      local pad = (" "):rep(math.max(1, inner - width(row) - width(right)))
      local full = row .. pad .. right
      local path_hl = (f.state == "pending" or f.state == "skipped") and "KitBuildPending"
        or f.state == "writing" and "KitBuildActive"
        or f.state == "failed" and "KitBuildFail"
        or "KitBuildPath"
      add(lines, marks, full, {
        { 2, 2 + #mark[1], mark[2] },
        { 2 + #mark[1] + 1, #row, path_hl },
        { #row + #pad, #full, "KitBuildMuted" },
      })
      V.rows[#lines] = f.path
      if f.state == "writing" then
        V.bands[#lines] = "KitBuildRow"
      end
    end
    add(lines, marks, "")
  end

  if #run.checks > 0 then
    heading "CHECKS"
    for _, c in ipairs(run.checks) do
      local mark = ({
        running = { spin, "KitBuildActive" },
        done = { "●", "KitBuildDone" },
        failed = { "✗", "KitBuildFail" },
      })[c.state] or { "○", "KitBuildPending" }
      local row = ("  %s %s"):format(mark[1], c.label)
      local label_hl = c.state == "failed" and "KitBuildFail"
        or c.state == "done" and "KitBuildPath"
        or "KitBuildPending"
      add(lines, marks, row, { { 2, 2 + #mark[1], mark[2] }, { 2 + #mark[1] + 1, #row, label_hl } })
    end
    add(lines, marks, "")
  end

  return lines, marks
end

-- ── Feed ─────────────────────────────────────────────────────────────────────

---@param run BuildRun
---@return string[], table
local function feed(run)
  local lines, marks = {}, {}
  for _, e in ipairs(run.feed) do
    if e.kind == "step" then
      if #lines > 0 then
        add(lines, marks, "")
      end
      local title = (e.title or ""):lower()
      local row = title .. "  " .. e.text .. (e.meta and ("  · " .. e.meta) or "")
      add(lines, marks, row, { { 0, #title, "KitBuildActive" }, { #title, #row, "KitBuildMuted" } })
    else
      local prefix = ({ ["in"] = "  → ", out = "  ← ", info = "  · ", fail = "  ✗ " })[e.kind] or "  "
      local hl = ({ ["in"] = "KitBuildPath", out = "KitBuildDone", info = "KitBuildMuted", fail = "KitBuildFail" })[e.kind]
      local body = vim.split(e.text, "\n", { plain = true })
      local meta = e.meta and vim.split(e.meta, "\n", { plain = true }) or {}
      local first = prefix .. body[1]
      local row = first .. (#meta == 1 and ("   " .. meta[1]) or "")
      if #meta > 1 then -- a tool's output: under the line, not after it
        vim.list_extend(body, meta)
      end
      add(lines, marks, row, {
        { 0, #prefix, hl },
        { #prefix, #first, e.kind == "info" and "KitBuildMuted" or nil },
        { #first, #row, "KitBuildMuted" },
      })
      for k = 2, #body do
        add(lines, marks, "    " .. body[k], { { 0, 4 + #body[k], "KitBuildMuted" } })
      end
    end
  end
  return lines, marks
end

--- Draws every pane from the state (coalesced: one draw per tick)
local function draw()
  V.pending_draw = false
  local run = state.run
  if not run or not shown() then
    return
  end
  if buf_ok(V.left) then
    local lines, marks = left(run)
    local cursor = win_ok(V.wl) and vim.api.nvim_win_get_cursor(V.wl)
    paint(V.left, lines, marks, V.bands)
    if cursor then
      pcall(vim.api.nvim_win_set_cursor, V.wl, { math.min(cursor[1], #lines), cursor[2] })
    end
  end
  if buf_ok(V.feed) then
    local before = vim.api.nvim_buf_line_count(V.feed)
    local lines, marks = feed(run)
    paint(V.feed, lines, marks)
    if win_ok(V.wf) and vim.api.nvim_get_current_win() ~= V.wf and #lines ~= before then
      pcall(vim.api.nvim_win_set_cursor, V.wf, { math.max(1, #lines), 0 })
    end
  end
  pcall(vim.cmd.redrawstatus)
end

local function request_draw()
  if V.pending_draw then
    return
  end
  V.pending_draw = true
  vim.schedule(draw)
end

state.subscribe(request_draw)

-- the chips and the statusline take their colors from the theme: again when it changes
vim.api.nvim_create_autocmd({ "ColorScheme", "User" }, {
  group = vim.api.nvim_create_augroup("AgentKitBuildColors", { clear = true }),
  callback = function(ev)
    if ev.event == "ColorScheme" or ev.match == "NvThemeReload" then
      highlights()
      request_draw()
    end
  end,
})

local function animate()
  if V.timer then
    return
  end
  V.timer = vim.uv.new_timer()
  V.timer:start(
    0,
    90,
    vim.schedule_wrap(function()
      if not shown() then
        if V.timer then
          V.timer:stop()
          V.timer:close()
          V.timer = nil
        end
        return
      end
      if state.run and state.run.running then
        V.frame = V.frame + 1
        draw()
      end
    end)
  )
end

-- ── Code pane ────────────────────────────────────────────────────────────────

---@param path string
local function show_code(path)
  if not win_ok(V.wc) or not buf_ok(V.code) then
    return
  end
  if vim.api.nvim_win_get_buf(V.wc) ~= V.code then
    vim.api.nvim_win_set_buf(V.wc, V.code)
  end
  local ft = vim.filetype.match { filename = path } or ""
  if vim.bo[V.code].filetype ~= ft then
    vim.bo[V.code].filetype = ft
  end
end

---@param lines string[]
local function set_code(lines)
  if not buf_ok(V.code) then
    return
  end
  vim.bo[V.code].modifiable = true
  vim.api.nvim_buf_set_lines(V.code, 0, -1, false, lines)
  vim.bo[V.code].modifiable = false
  if win_ok(V.wc) and vim.api.nvim_win_get_buf(V.wc) == V.code then
    pcall(vim.api.nvim_win_set_cursor, V.wc, { #lines > 0 and #lines or 1, 0 })
  end
end

local function stop_typing()
  if V.typing then
    V.typing:stop()
    V.typing:close()
    V.typing = nil
  end
end

---@param path string
---@param what string
local function code_bar(path, what)
  local run = state.run
  local phase = run and (run.phase == "fix" and "fixes" or run.phase == "use" and "use" or "files")
  local model = run and require("agent.kit.build").model(phase) or ""
  winbar(V.wc, ("%s  ·  %s  ·  %s"):format(path, what, model))
end

--- A new file is on its way: the pane keeps the last one (no blank screen while the model thinks)
---@param path string
---@param label string?
function M.code_start(path, label)
  V.text, V.current, V.streamed = "", path, false
  if shown() then
    code_bar(path, (label or "writing") .. "…")
  end
end

--- More of the file arrived (backends that stream)
---@param delta string
function M.code_stream(delta)
  if not V.current then
    return
  end
  if not V.streamed then
    stop_typing()
    if shown() then
      show_code(V.current)
    end
  end
  V.streamed = true
  V.text = V.text .. delta
  if shown() then
    set_code(vim.split(V.text, "\n", { plain = true }))
  end
end

--- A document that grows while the model writes it (the plan): shown as it is now, the cursor following its end
---@param path string
---@param content string
function M.code_live(path, content)
  stop_typing()
  V.current, V.text, V.streamed = path, content, true
  if not shown() or not win_ok(V.wc) then
    return
  end
  show_code(path)
  set_code(vim.split(content, "\n", { plain = true }))
end

--- The file is written: typed out when nothing streamed (~0.6 s), then it stays
---@param path string
---@param content string
---@param label string?
---@param instant boolean? shown at once (the plan you asked to see), not typed out
function M.code_done(path, content, label, instant)
  V.text, V.current = content, path -- what the pane holds now (a relayout redraws it with this file's syntax)
  if not shown() or not win_ok(V.wc) then
    return
  end
  local lines = vim.split((content:gsub("\n$", "")), "\n", { plain = true })
  stop_typing()
  show_code(path)
  code_bar(path, ("%s · %d lines"):format(label or "written", #lines))
  if V.streamed or instant then
    set_code(lines)
    if instant then
      pcall(vim.api.nvim_win_set_cursor, V.wc, { 1, 0 })
    end
    return
  end
  local count, step = 0, math.max(1, math.ceil(#lines / 24))
  set_code {}
  V.typing = vim.uv.new_timer()
  V.typing:start(
    0,
    25,
    vim.schedule_wrap(function()
      if not V.typing then
        return
      end
      if not shown() then
        return stop_typing()
      end
      count = math.min(#lines, count + step)
      set_code(vim.list_slice(lines, 1, count))
      if count >= #lines then
        stop_typing()
      end
    end)
  )
end

-- ── Layout ───────────────────────────────────────────────────────────────────

---@param win integer
---@param opts table?
local function window_style(win, opts)
  local wo = vim.wo[win]
  wo.number, wo.relativenumber, wo.signcolumn, wo.foldcolumn = false, false, "no", "0"
  wo.wrap, wo.list, wo.cursorline, wo.spell = false, false, false, false
  wo.winbar = ""
  for k, v in pairs(opts or {}) do
    wo[k] = v
  end
end

--- (Re)builds the panes of the tab from the kept buffers: top and bottom lines always, the code and the feed when shown
function M.layout(focus)
  if not shown() then
    return
  end
  vim.api.nvim_set_current_tabpage(V.tab)
  -- which panes: z = the code alone; otherwise the list, the code and the feed as toggled (never none)
  local left, code, feed = V.show_left, V.show_code, V.show_feed
  if V.zoom then
    left, code, feed = false, true, false
  elseif not (left or code or feed) then
    left = true
  end
  -- keep one window of the tab, close the rest, rebuild around it
  local base = vim.api.nvim_tabpage_list_wins(V.tab)[1]
  for _, w in ipairs { V.wl, V.wc, V.wf } do
    if win_ok(w) and vim.api.nvim_win_get_tabpage(w) == V.tab then
      base = w
      break
    end
  end
  vim.api.nvim_set_current_win(base)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(V.tab)) do
    if w ~= base then
      pcall(vim.api.nvim_win_close, w, true)
    end
  end
  V.wl, V.wc, V.wf = nil, nil, nil
  local function place(buf)
    vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), buf)
    return vim.api.nvim_get_current_win()
  end
  if left then
    V.wl = place(V.left)
    if code or feed then
      vim.cmd "rightbelow vsplit"
    end
  end
  if code then
    V.wc = place(V.code)
    if feed then
      vim.cmd "belowright split"
    end
  end
  if feed then
    V.wf = place(V.feed)
  end
  if V.wl and (V.wc or V.wf) then
    vim.api.nvim_win_set_width(V.wl, LEFT_W + 2)
  end
  if V.wc and V.wf then
    vim.api.nvim_win_set_height(V.wf, math.max(8, math.floor(vim.o.lines * 0.3)))
  end
  if V.wl then
    window_style(V.wl, { cursorline = true, winfixwidth = V.wc ~= nil or V.wf ~= nil })
  end
  if V.wc then
    -- every line visible: long lines wrap (never a horizontal scroll), code keeps its indent on the wrapped part
    local prose = V.current and V.current:match "%.md$"
    window_style(V.wc, { number = not prose, wrap = true, linebreak = true, breakindent = true })
    winbar(V.wc, "code · each file as it is written · c hides it")
    if V.current then
      winbar(V.wc, V.current .. (V.zoom and "  ·  z back  ·  ⇥ pane  ·  q hide" or ""))
      if V.text ~= "" then
        show_code(V.current)
        set_code(vim.split(V.text, "\n", { plain = true }))
        if prose then
          pcall(vim.api.nvim_win_set_cursor, V.wc, { 1, 0 }) -- read from the top
        end
      end
    end
  end
  if V.wf then
    window_style(V.wf, { wrap = true, linebreak = true })
    winbar(V.wf, "feed · what each request carried and cost · f hides it")
  end
  local target = (focus == "code" and V.wc) or (focus == "feed" and V.wf) or V.wl or V.wc or V.wf
  vim.api.nvim_set_current_win(target)
  draw()
end

--- Tab / Shift-Tab: the cursor to the next (or previous) visible pane
---@param step integer
local function cycle(step)
  local wins = vim.tbl_filter(win_ok, { V.wl, V.wc, V.wf })
  if #wins < 2 then
    return
  end
  local cur = vim.api.nvim_get_current_win()
  local at = 1
  for i, w in ipairs(wins) do
    if w == cur then
      at = i
    end
  end
  vim.api.nvim_set_current_win(wins[(at - 1 + step) % #wins + 1])
end

--- `p`: the request a file was written from, in the code pane (shown if it was hidden)
---@param path string
local function show_prompt(path)
  local sent = require("agent.kit.build").sent(path)
  if not sent then
    return require("utils.log").info "Build: this session has not sent that file's request (the history has every one: <leader>ah)"
  end
  stop_typing()
  local lines = { "# What " .. path .. " was written from", "", "## System prompt (cached between files)", "" }
  vim.list_extend(lines, vim.split(sent.system, "\n", { plain = true }))
  vim.list_extend(lines, { "", "## Message", "" })
  vim.list_extend(lines, vim.split(sent.prompt, "\n", { plain = true }))
  -- it becomes what the pane holds: z zooms on it, a relayout keeps it
  V.current, V.text, V.streamed = "prompt.md", table.concat(lines, "\n"), true
  V.show_code = true
  M.layout "code"
  winbar(
    V.wc,
    ("%s  ·  request  ·  %s chars%s"):format(path, size(#sent.system + #sent.prompt), V.zoom and "  ·  z back" or "")
  )
end

-- ── Keys ─────────────────────────────────────────────────────────────────────

---@return string?
local function path_under_cursor()
  if not win_ok(V.wl) then
    return nil
  end
  return V.rows[vim.api.nvim_win_get_cursor(V.wl)[1]]
end

local function close()
  if shown() and #vim.api.nvim_list_tabpages() > 1 then
    pcall(vim.cmd.tabclose, vim.api.nvim_tabpage_get_number(V.tab))
  end
  local run = state.run
  if run and run.running then
    require("utils.log").info "Build: still running · the statusline shows it · <leader>aSb brings the view back"
  end
end

---@param buf integer
local function keys(buf)
  local build = require "agent.kit.build"
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, desc = "Build " .. desc })
  end
  map("q", close, "hide")
  map("<CR>", function()
    local run = state.run
    local path = path_under_cursor()
    if path and run and vim.api.nvim_get_current_win() == V.wl and (run.running or run.phase == "done") then
      local full = run.root .. "/" .. path
      if vim.uv.fs_stat(full) then
        if not V.show_code then
          V.show_code = true
          M.layout()
        end
        if win_ok(V.wc) then
          vim.api.nvim_set_current_win(V.wc)
          vim.cmd.edit(vim.fn.fnameescape(full))
          winbar(V.wc, path)
        end
      end
      return
    end
    build.go()
  end, "next step or open file")
  map("x", function()
    local run = state.run
    if run and run.running then
      return build.stop()
    end
    local path = path_under_cursor()
    if path then
      build.toggle_skip(path)
    end
  end, "stop or skip file")
  map("c", function()
    V.show_code, V.zoom = not V.show_code, false
    M.layout()
  end, "code pane")
  map("l", function()
    V.show_left, V.zoom = not V.show_left, false
    M.layout()
  end, "files pane")
  map("z", function()
    V.zoom = not V.zoom
    M.layout(V.zoom and "code" or nil)
  end, "focus code")
  map("<Tab>", function()
    cycle(1)
  end, "next pane")
  map("<S-Tab>", function()
    cycle(-1)
  end, "previous pane")
  map("f", function()
    V.show_feed, V.zoom = not V.show_feed, false
    M.layout()
  end, "feed pane")
  map("p", function()
    local path = path_under_cursor() or (state.run and state.run.phase ~= "ready" and "plan.json")
    if path then
      show_prompt(path)
    end
  end, "show request")
  map("r", build.recheck, "check again")
  map("P", build.show_plan, "show the plan")
  map("n", build.restart, "new plan")
  map("X", build.clean, "clean the build")
  for i, phase in ipairs(build.TIERED) do
    map(tostring(i), function()
      build.cycle(phase)
    end, phase .. " tier")
  end
  map("+", function()
    build.fix_rounds(1)
  end, "more fix rounds")
  map("-", function()
    build.fix_rounds(-1)
  end, "fewer fix rounds")
end

--- Opens the view (or goes to it)
function M.open()
  highlights()
  if V.tab == nil then -- first open of the session: the panes the settings ask for
    local view = (((require("core.settings").agent.kit or {}).build or {}).view or {})
    V.show_code = view.code ~= false
    V.show_feed = view.feed ~= false
  end
  if shown() then
    vim.api.nvim_set_current_tabpage(V.tab)
    request_draw()
    return animate()
  end
  for name, field in pairs {
    ["build://files"] = "left",
    ["build://code"] = "code",
    ["build://feed"] = "feed",
  } do
    if not buf_ok(V[field]) then
      V[field] = scratch(name)
      keys(V[field])
      if field ~= "code" then
        vim.bo[V[field]].filetype = "agentbuild" -- the statusline's build sections (lualine extension)
      end
    end
  end
  vim.cmd "tabnew"
  V.tab = vim.api.nvim_get_current_tabpage()
  local blank = vim.api.nvim_get_current_buf()
  V.wl = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(V.wl, V.left)
  if vim.api.nvim_buf_is_valid(blank) and blank ~= V.left then
    pcall(vim.api.nvim_buf_delete, blank, { force = true })
  end
  M.layout()
  animate()
end

---@return boolean
function M.shown()
  return shown()
end

return M
