-- ── Build with agent: the view ───────────────────────────────────────────────
-- A tab that draws build/state.lua, so it can be closed and opened again at any moment (the build goes on without it):
--   left    the banner (block letters; the theme's gradient runs across them while the build works), the phases
--           (plan ━ review ━ write ━ check ━ fix ━ done), the progress bar, money, tokens, cache and time, the model of
--           each phase, then what this phase needs: the documents (ready), the estimate (review), the files with their
--           lines and cost, the checks; the keys of the moment at the bottom
--   top     the file being written, typed out as it arrives (it stays until the next one lands); `p` shows the request a
--           file was written from (system prompt and message), ⏎ the file itself
--   bottom  the feed: each step, what every request carried (→) and what it cost (←)
-- Buffers are kept (hidden, never wiped) and every window call checks the window is there: closing a pane by hand, opening
-- a file in the code pane or closing the tab never breaks the build.
require("agent.ui.highlights").ensure()

local state = require "agent.kit.build.state"

local M = {}

local NS = vim.api.nvim_create_namespace "AgentKitBuild"
local SPIN = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local BANNER = { "█▄▄ █ █ █ █   █▀▄", "█▄█ █▄█ █ █▄▄ █▄▀" }
local STEPS = { "plan", "review", "write", "check", "fix", "done" }
local LEFT_W = 52

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
  KitBuildBarEmpty = "Comment",
}

local GRAD = 24 -- gradient steps

local function highlights()
  for name, link in pairs(LINKS) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
  local function rgb(name)
    local c = vim.api.nvim_get_hl(0, { name = name, link = false }).fg or 0xd79921
    return { math.floor(c / 65536) % 256, math.floor(c / 256) % 256, c % 256 }
  end
  local a, b = rgb "DiagnosticWarn", rgb "Function"
  for i = 0, GRAD - 1 do
    local t = i / (GRAD - 1)
    local mix = {}
    for k = 1, 3 do
      mix[k] = math.floor(a[k] + (b[k] - a[k]) * t + 0.5)
    end
    vim.api.nvim_set_hl(0, "KitBuildGrad" .. i, { fg = mix[1] * 65536 + mix[2] * 256 + mix[3], bold = true })
  end
end

---@class BuildViewState
local V = {
  tab = nil, ---@type integer?
  left = nil, ---@type integer? buffers
  code = nil, ---@type integer?
  feed = nil, ---@type integer?
  wl = nil, ---@type integer? windows
  wc = nil, ---@type integer?
  wf = nil, ---@type integer?
  rows = {}, ---@type table<integer, string> left row → file path
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

---@param win integer?
---@param text string
local function winbar(win, text)
  if win_ok(win) then
    vim.wo[win].winbar = "%#KitBuildTitle# " .. text:gsub("%%", "%%%%")
  end
end

-- ── Left pane ────────────────────────────────────────────────────────────────

--- The phase the stepper shows as current (a stopped or failed run shows where it was)
---@param run BuildRun
---@return string
local function at(run)
  if vim.tbl_contains(STEPS, run.phase) then
    return run.phase
  end
  if run.phase == "ready" then
    return "ready"
  end
  return run.at or "write"
end

---@param lines string[]
---@param marks table
---@param text string
---@param hls { [1]: integer, [2]: integer, [3]: string }[]?
local function add(lines, marks, text, hls)
  lines[#lines + 1] = text
  marks[#lines] = hls
end

---@param run BuildRun
---@return string[], table
local function left(run)
  local lines, marks = {}, {}
  V.rows = {}
  local spin = SPIN[V.frame % #SPIN + 1]
  add(lines, marks, "")
  -- banner: the gradient runs across it while the build works
  for _, row in ipairs(BANNER) do
    local hls, col = {}, 2
    local chars = vim.fn.split(row, "\\zs")
    for i, ch in ipairs(chars) do
      local shift = run.running and V.frame or 0
      local pos = ((i - 1) * (GRAD - 1) / math.max(1, #chars - 1) + shift) % (2 * (GRAD - 1))
      local idx = math.floor(pos <= GRAD - 1 and pos or 2 * (GRAD - 1) - pos)
      hls[#hls + 1] = { col, col + #ch, "KitBuildGrad" .. idx }
      col = col + #ch
    end
    add(lines, marks, "  " .. row, hls)
  end
  add(lines, marks, "  " .. run.name, { { 2, 2 + #run.name, "KitBuildTitle" } })
  add(lines, marks, "")

  -- phases
  local now = at(run)
  local idx = 0
  for i, s in ipairs(STEPS) do
    if s == now then
      idx = i
    end
  end
  local text, hls = "  ", {}
  for i, s in ipairs(STEPS) do
    local hl = (i < idx and "KitBuildDone") or (i == idx and "KitBuildActive") or "KitBuildPending"
    if run.phase == "done" and s == "done" then
      hl = "KitBuildDone"
    end
    local label = (i == idx and run.running) and (spin .. " " .. s) or s
    hls[#hls + 1] = { #text, #text + #label, hl }
    text = text .. label
    if i < #STEPS then
      text = text .. " ━ "
      hls[#hls + 1] = { #text - #" ━ " + 1, #text - 1, "KitBuildPending" }
    end
  end
  add(lines, marks, text, hls)
  add(lines, marks, "")

  -- progress, money, time
  local done, total = state.progress()
  if total > 0 and run.phase ~= "review" and run.phase ~= "ready" then
    local width = 30
    local fill = math.floor(width * done / total + 0.5)
    local bar = ("█"):rep(fill) .. ("░"):rep(width - fill)
    local label = ("  %s  %d/%d"):format(bar, done, total)
    add(lines, marks, label, {
      { 2, 2 + #("█"):rep(fill), "KitBuildBarFill" },
      { 2 + #("█"):rep(fill), 2 + #bar, "KitBuildBarEmpty" },
    })
  end
  local t = run.totals
  local secs = require("agent.kit.build").elapsed()
  local cached = t.tokens_in > 0 and math.floor(100 * t.cached / t.tokens_in + 0.5) or 0
  local money = ("$%.3f"):format(t.cost)
  local meta = ("  %s · %s in · %d%% cached · %s out · %dm%02ds"):format(
    money,
    size(t.tokens_in),
    cached,
    size(t.tokens_out),
    math.floor(secs / 60),
    secs % 60
  )
  add(lines, marks, meta, { { 2, 2 + #money, "KitBuildMoney" }, { 2 + #money, #meta, "KitBuildMuted" } })
  if run.outcome then
    local hl = run.outcome:find "^✓" and "KitBuildDone"
      or run.outcome:find "^✗" and "KitBuildFail"
      or "KitBuildActive"
    add(lines, marks, "  " .. run.outcome, { { 2, 2 + #run.outcome, hl } })
  end
  add(lines, marks, "")

  -- models
  local build = require "agent.kit.build"
  local editable = not run.running and (run.phase == "ready" or run.phase == "review" or run.phase == "stopped")
  add(lines, marks, "  MODELS", { { 2, 8, "KitBuildMuted" } })
  for i, phase in ipairs { "plan", "files", "fixes" } do
    local key = editable and tostring(i) or " "
    local label = build.model(phase)
    local row = ("  %s %-6s %-26s %s"):format(key, phase, label, run.tiers[phase])
    add(lines, marks, row, {
      { 2, 3, "KitBuildKey" },
      { 4, 10, "KitBuildMuted" },
      { 11, 11 + #label, "KitBuildTitle" },
      { #row - #run.tiers[phase], #row, "KitBuildMuted" },
    })
  end
  local fixes = ("  %s fix rounds  %d"):format(editable and "±" or " ", run.max_fixes)
  add(lines, marks, fixes, { { 2, 4, "KitBuildKey" }, { 5, #fixes, "KitBuildMuted" } })
  add(lines, marks, "")

  -- what this phase needs
  if run.phase == "ready" then
    add(lines, marks, "  DOCUMENTS", { { 2, 11, "KitBuildMuted" } })
    for _, d in ipairs(run.docs) do
      local row = ("  ● %-12s %6s chars"):format(d.file, size(d.chars))
      add(lines, marks, row, { { 2, 5, "KitBuildDone" }, { 5, 18, "KitBuildPath" }, { 18, #row, "KitBuildMuted" } })
    end
    add(lines, marks, "")
    local est = require("agent.kit.build").plan_estimate()
    local note = ("  ⏎ plan · 1 request · ~%s in%s"):format(
      size(est.tokens),
      est.cost and (" · ~$%.3f"):format(est.cost) or ""
    )
    add(lines, marks, note, { { 2, 5, "KitBuildKey" }, { 5, #note, "KitBuildMoney" } })
    add(lines, marks, "")
  end
  if run.phase == "review" and run.estimate then
    add(lines, marks, "  ESTIMATE", { { 2, 10, "KitBuildMuted" } })
    local e = run.estimate
    local cost = e.cost and ("~$%.3f"):format(e.cost) or "no price yet"
    local row = ("  %d files · ~%s in · %s with the cache"):format(e.files or 0, size(e.tokens), cost)
    add(lines, marks, row, { { 2, #row, "KitBuildMoney" } })
    if e.nocache then
      local r1 = ("  (~$%.3f without it: the documents are shared by every file)"):format(e.nocache)
      add(lines, marks, r1, { { 2, #r1, "KitBuildMuted" } })
    end
    if (run.replaced or 0) > 0 then
      local r2 = ("  replaces %d existing file%s (old ones to the trash)"):format(
        run.replaced,
        run.replaced == 1 and "" or "s"
      )
      add(lines, marks, r2, { { 2, #r2, "KitBuildActive" } })
    end
    if run.stale and #run.stale > 0 then
      local r3 = ("  %d leftover%s of the last build go to the trash"):format(#run.stale, #run.stale == 1 and "" or "s")
      add(lines, marks, r3, { { 2, #r3, "KitBuildActive" } })
    end
    add(lines, marks, "")
  end

  -- files
  if #run.files > 0 then
    local head = "  FILES" .. (" "):rep(LEFT_W - 7 - #"lines   cost") .. "lines   cost"
    add(lines, marks, head, { { 2, #head, "KitBuildMuted" } })
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
        right = ("%5d  %s"):format(f.lines, f.cost and ("$%.4f"):format(f.cost):gsub("^%$0", "$") or "")
      elseif run.phase == "review" and f.estimate and f.state ~= "skipped" then
        right = ("~%s"):format(size(f.estimate))
      end
      local room = LEFT_W - 6 - vim.fn.strdisplaywidth(right)
      local path = f.path
      if vim.fn.strdisplaywidth(path) > room then
        path = "…" .. path:sub(-(room - 1))
      end
      local row = ("  %s %s"):format(mark[1], path)
      local pad = (" "):rep(math.max(1, LEFT_W - vim.fn.strdisplaywidth(row) - vim.fn.strdisplaywidth(right)))
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
    end
    add(lines, marks, "")
  end

  -- checks
  if #run.checks > 0 then
    add(lines, marks, "  CHECKS", { { 2, 8, "KitBuildMuted" } })
    for _, c in ipairs(run.checks) do
      local mark = ({
        running = { spin, "KitBuildActive" },
        done = { "●", "KitBuildDone" },
        failed = { "✗", "KitBuildFail" },
      })[c.state] or { "○", "KitBuildPending" }
      local row = ("  %s %s"):format(mark[1], c.label)
      add(lines, marks, row, { { 2, 2 + #mark[1], mark[2] }, { 2 + #mark[1] + 1, #row, "KitBuildMuted" } })
    end
    add(lines, marks, "")
  end

  -- keys of the moment
  local keys
  if run.running then
    keys = "x stop · q hide, it goes on · p prompt"
  elseif run.phase == "ready" then
    keys = "⏎ plan · 1 2 3 tier · ± fixes · q close"
  elseif run.phase == "review" then
    keys = "⏎ build · x skip · 2 3 tier · n replan · q"
  elseif run.phase == "done" then
    keys = "⏎ open · p prompt · r recheck · n replan · q"
  else
    keys = "⏎ resume · r recheck · n replan · p · q"
  end
  add(lines, marks, "  " .. keys, { { 2, 2 + #keys, "KitBuildKey" } })
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
      local title = " " .. (e.title or "") .. " "
      local row = "━━" .. title .. "━━ " .. e.text .. (e.meta and ("  · " .. e.meta) or "")
      local t0 = #"━━"
      add(lines, marks, row, {
        { 0, t0, "KitBuildMuted" },
        { t0, t0 + #title, "KitBuildActive" },
        { t0 + #title, #row, "KitBuildMuted" },
      })
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

---@param buf integer
---@param lines string[]
---@param marks table
local function paint(buf, lines, marks)
  vim.bo[buf].modifiable = true
  for i, l in ipairs(lines) do
    if l:find("\n", 1, true) then -- a line must not carry a newline (set_lines refuses it)
      lines[i] = l:gsub("\n", " ")
    end
  end
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
end

--- Draws the left pane and the feed from the state (cheap; coalesced to one draw per tick)
local function draw()
  V.pending_draw = false
  local run = state.run
  if not run or not shown() then
    return
  end
  if buf_ok(V.left) then
    local lines, marks = left(run)
    local cursor = win_ok(V.wl) and vim.api.nvim_win_get_cursor(V.wl)
    paint(V.left, lines, marks)
    if cursor then
      pcall(vim.api.nvim_win_set_cursor, V.wl, { math.min(cursor[1], #lines), cursor[2] })
    end
  end
  if buf_ok(V.feed) then
    local before = vim.api.nvim_buf_line_count(V.feed)
    local lines, marks = feed(run)
    paint(V.feed, lines, marks)
    -- follow the end unless you are reading the feed
    if win_ok(V.wf) and vim.api.nvim_get_current_win() ~= V.wf and #lines ~= before then
      pcall(vim.api.nvim_win_set_cursor, V.wf, { math.max(1, #lines), 0 })
    end
  end
end

local function request_draw()
  if V.pending_draw then
    return
  end
  V.pending_draw = true
  vim.schedule(draw)
end

state.subscribe(request_draw)

--- The spinner, the banner and the clock while the view is open and the build works
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
  local model = run and require("agent.kit.build").model(run.phase == "fix" and "fixes" or "files") or ""
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

--- The file is written: typed out when nothing streamed (~0.6 s), then it stays
---@param path string
---@param content string
---@param label string?
function M.code_done(path, content, label)
  if not shown() then
    return
  end
  local lines = vim.split((content:gsub("\n$", "")), "\n", { plain = true })
  stop_typing()
  show_code(path)
  code_bar(path, ("%s · %d lines"):format(label or "written", #lines))
  if V.streamed then
    return set_code(lines)
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

--- `p`: the request a file was written from, in the code pane
---@param path string
local function show_prompt(path)
  local sent = require("agent.kit.build").sent(path)
  if not sent then
    return require("utils.log").info "Build: this session has not sent that file's request (the history has every one: <leader>ah)"
  end
  stop_typing()
  show_code "prompt.md"
  local lines = { "# What " .. path .. " was written from", "", "## System prompt (cached between files)", "" }
  vim.list_extend(lines, vim.split(sent.system, "\n", { plain = true }))
  vim.list_extend(lines, { "", "## Message", "" })
  vim.list_extend(lines, vim.split(sent.prompt, "\n", { plain = true }))
  set_code(lines)
  pcall(vim.api.nvim_win_set_cursor, V.wc, { 1, 0 })
  winbar(V.wc, ("%s  ·  request  ·  %s chars"):format(path, size(#sent.system + #sent.prompt)))
end

-- ── Open / close ─────────────────────────────────────────────────────────────

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
      if win_ok(V.wc) and vim.uv.fs_stat(run.root .. "/" .. path) then
        vim.api.nvim_set_current_win(V.wc)
        vim.cmd.edit(vim.fn.fnameescape(run.root .. "/" .. path))
        winbar(V.wc, path)
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
  map("p", function()
    local path = path_under_cursor() or (state.run and state.run.phase ~= "ready" and "plan.json")
    if path then
      show_prompt(path)
    end
  end, "show request")
  map("r", build.recheck, "check again")
  map("n", build.restart, "new plan")
  map("1", function()
    build.cycle "plan"
  end, "plan tier")
  map("2", function()
    build.cycle "files"
  end, "files tier")
  map("3", function()
    build.cycle "fixes"
  end, "fixes tier")
  map("+", function()
    build.fix_rounds(1)
  end, "more fix rounds")
  map("-", function()
    build.fix_rounds(-1)
  end, "fewer fix rounds")
end

--- Opens the view (or goes to it): the tab, its three panes, the keys, the animation
function M.open()
  highlights()
  if shown() then
    vim.api.nvim_set_current_tabpage(V.tab)
    request_draw()
    return animate()
  end
  for name, field in pairs { ["build://plan"] = "left", ["build://code"] = "code", ["build://feed"] = "feed" } do
    if not buf_ok(V[field]) then
      V[field] = scratch(name)
      keys(V[field])
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
  vim.cmd "vsplit"
  V.wc = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(V.wc, V.code)
  vim.cmd "belowright split"
  V.wf = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(V.wf, V.feed)
  vim.api.nvim_win_set_width(V.wl, LEFT_W + 2)
  vim.api.nvim_win_set_height(V.wf, math.max(10, math.floor(vim.o.lines * 0.32)))
  for _, w in ipairs { V.wl, V.wc, V.wf } do
    local wo = vim.wo[w]
    wo.number, wo.relativenumber, wo.signcolumn, wo.foldcolumn = false, false, "no", "0"
    wo.wrap, wo.list, wo.cursorline, wo.spell = false, false, false, false
  end
  vim.wo[V.wc].number = true
  vim.wo[V.wl].winfixwidth = true
  vim.wo[V.wl].cursorline = true
  vim.wo[V.wf].wrap = true
  vim.wo[V.wf].linebreak = true
  winbar(V.wl, "agent build")
  winbar(V.wc, V.current and (V.current .. "  ·  the last file") or "the code appears here, file by file")
  winbar(V.wf, "feed · what each request carried → and what it cost ←")
  if V.current and V.text ~= "" then
    show_code(V.current)
    set_code(vim.split(V.text, "\n", { plain = true }))
  end
  vim.api.nvim_set_current_win(V.wl)
  draw()
  animate()
end

---@return boolean
function M.shown()
  return shown()
end

return M
