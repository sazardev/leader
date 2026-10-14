-- ── Commit panel ─────────────────────────────────────────────────────────────
-- ONE experience for committing, as clear as <leader>a: on top, WHAT gets committed (staged vs. not staged,
-- with +/− per file); below, the message with live Conventional Commits validation and a line saying what the
-- agent will do (model, what it reads, how much it costs) BEFORE spending anything. All keyboard-driven, with the theme colors.
--
--   files   Space stage/unstage · a all · u none · p diff · Tab message        message   Ctrl-s commit · Ctrl-g AI · Ctrl-t type · Ctrl-o scope
--
-- Entry points (<leader>G menu): `c` opens the panel, `m` opens it and asks the AI for the draft, `a` rewrites the last
-- commit (amend). All three share the same panel.
local ai = require "commit.ai"
local conventional = require "commit.conventional"
local git = require "commit.git"
local log = require "utils.log"
local text = require "agent.text"

require("commit.highlights").ensure()

local M = {}

local NS = vim.api.nvim_create_namespace "commit.panel"
local FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local MSG_HEIGHT = 8
local WINHL = "NormalFloat:AgentFloat,FloatBorder:AgentBorder,FloatTitle:AgentTitle,FloatFooter:AgentHint"

---@class CommitState
---@field root string
---@field amend boolean
---@field head { hash: string, subject: string, message: string }?
---@field entries CommitEntry[]
---@field rows table<integer, { entry: CommitEntry?, group: string? }>
---@field nlines integer
---@field branch CommitBranch
---@field files_buf integer
---@field files_win integer
---@field msg_buf integer
---@field msg_win integer
---@field status_buf integer
---@field status_win integer
---@field ai { state: "idle"|"running"|"done"|"error", handle: vim.SystemObj?, t0: integer?, secs: number?, usage: table?, err: string?, timer: uv.uv_timer_t?, model: string? }
---@field busy string?    "committing…" while git commit runs (hooks may take a while)
---@field preview integer?
---@field closing boolean?
---@type CommitState?
local S

local function cfg()
  return require("core.settings").git.commit
end

-- ── helpers ──────────────────────────────────────────────────────────────────

---@return string[]
local function staged_paths()
  local list = {}
  for _, e in ipairs(S.entries) do
    if e.staged then
      list[#list + 1] = e.path
    end
  end
  return list
end

---@return string[]
local function pending_paths()
  local list = {}
  for _, e in ipairs(S.entries) do
    if not e.staged or e.partial then
      list[#list + 1] = e.path
    end
  end
  return list
end

---@param chunks table[] { text, hl }[]
---@param width integer
---@param keep integer  how many leading chunks are never trimmed
---@return table[]
local function fit(chunks, width, keep)
  local function total()
    local n = 0
    for _, c in ipairs(chunks) do
      n = n + vim.fn.strdisplaywidth(c[1])
    end
    return n
  end
  while #chunks > keep and total() > width do
    table.remove(chunks)
  end
  return chunks
end

---@return integer
local function inner_width()
  -- flat: the demo's panel width (660px)
  return math.max(40, math.min(require("ui.flat").enabled() and 82 or 100, vim.o.columns - 6) - 2)
end

---@return boolean
local function alive()
  return S ~= nil and not S.closing and vim.api.nvim_win_is_valid(S.files_win) and vim.api.nvim_win_is_valid(S.msg_win)
end

-- ── windows ──────────────────────────────────────────────────────────────────

---@return table files_cfg, table msg_cfg, table status_cfg
local function layout()
  local width = inner_width()
  local rows = vim.o.lines
  local list_h = math.max(3, math.min(S.nlines, 14, rows - MSG_HEIGHT - 10))
  local total = list_h + MSG_HEIGHT + 5
  local top = math.max(0, math.floor((rows - total) / 2) - 1)
  if require("ui.flat").enabled() then
    top = math.min(top, 2) -- the demo's panel opens near the top, under the code it talks about
  end
  local left = math.floor((vim.o.columns - (width + 2)) / 2)
  local base =
    { relative = "editor", width = width, col = left, style = "minimal", border = require("ui.flat").border() }
  local msg_row = top + list_h + 2
  return vim.tbl_extend("force", base, { height = list_h, row = top }),
    vim.tbl_extend("force", base, { height = MSG_HEIGHT, row = msg_row }),
    -- the agent line goes right below the panel, borderless: it reads as the commit's status bar
    {
      relative = "editor",
      width = width + 2,
      height = 1,
      row = msg_row + MSG_HEIGHT + 2,
      col = left,
      style = "minimal",
      border = "none", -- borderless on purpose (not the global 'winborder')
      focusable = false,
      zindex = 40,
    }
end

--- Title and footer of the two windows (they change with the branch, the state and the validation)
local function chrome()
  if not alive() then
    return
  end
  local files_cfg, msg_cfg, status_cfg = layout()

  -- top: what and where
  local b = S.branch
  local where = b.upstream and ("%s → %s"):format(b.name, b.upstream) or ("%s (no upstream)"):format(b.name)
  -- flat: the whole title is one blue chip (`◆ Commit · main → origin/main ↑1`), like the demo's
  local flat = require("ui.flat").enabled()
  local sub = flat and "CommitHeader" or "AgentHint"
  local title = {
    { S.amend and (" ◆ Amend %s "):format(S.head and S.head.hash or "") or " ◆ Commit ", "CommitHeader" },
    { "· " .. where .. " ", sub },
  }
  if b.ahead > 0 then
    title[#title + 1] = { ("↑%d "):format(b.ahead), flat and sub or "CommitWarn" }
  end
  if b.behind > 0 then
    title[#title + 1] = { ("↓%d "):format(b.behind), flat and sub or "CommitWarn" }
  end
  files_cfg.title = title
  files_cfg.title_pos = "left"
  files_cfg.footer = {
    {
      " Space stage · a all · u none · p diff · Tab message · Ctrl-g AI · Ctrl-r review · q cancel ",
      "CommitHint",
    },
  }
  files_cfg.footer_pos = "center"
  vim.api.nvim_win_set_config(S.files_win, files_cfg)

  -- bottom: live Conventional Commits validation
  local line = vim.api.nvim_buf_get_lines(S.msg_buf, 0, 1, false)[1] or ""
  local c = conventional.check(line)
  local mtitle
  if S.busy then
    mtitle = { { (" %s %s "):format(FRAMES[math.floor(vim.uv.hrtime() / 1e8) % #FRAMES + 1], S.busy), "AgentStatus" } }
  elseif c.state == "empty" then
    local suggest = conventional.suggest_type(staged_paths())
    mtitle = {
      { " Message ", "CommitHeader" },
      { suggest and ("· suggested type: %s "):format(suggest) or "· type(scope): subject ", sub },
    }
  elseif c.state == "ok" and flat then
    -- the demo's: `Message` and the validation chip `✔ feat(go) · 44/72`, both on the blue bar
    local h = c.header
    local label = h.type .. (h.scope and ("(" .. h.scope .. ")") or "") .. (h.breaking and "!" or "")
    mtitle = {
      { " Message ", "CommitHeader" },
      { (" ✔ %s · %d/%d "):format(label, c.len, c.max), c.len > c.max - 8 and "CommitHeaderWarn" or "CommitHeader" },
    }
  elseif c.state == "ok" then
    local h = c.header
    local label = h.type .. (h.scope and ("(" .. h.scope .. ")") or "") .. (h.breaking and "!" or "")
    mtitle = {
      { " ✔ ", "CommitOk" },
      { label .. " ", "AgentTitle" },
      { ("· %d/%d "):format(c.len, c.max), c.len > c.max - 8 and "CommitWarn" or "AgentHint" },
    }
  elseif c.state == "incomplete" then
    mtitle =
      { { " ✔ ", "CommitOk" }, { c.header.type .. " ", "AgentTitle" }, { "· add the subject ", "CommitWarn" } }
  else
    mtitle =
      { { " ✘ ", "CommitErr" }, { c.err:gsub("^the first line must look like ", "expected ") .. " ", "CommitErr" } }
  end
  msg_cfg.title = mtitle
  msg_cfg.title_pos = "left"
  msg_cfg.footer = {
    {
      " Ctrl-s commit · Ctrl-g AI draft · Ctrl-r review · Ctrl-t type · Ctrl-o scope · Tab files · q cancel ",
      "CommitHint",
    },
  }
  msg_cfg.footer_pos = "center"
  vim.api.nvim_win_set_config(S.msg_win, msg_cfg)
  vim.api.nvim_win_set_config(S.status_win, status_cfg)
end

--- Agent line about the subject: what it will do, with which model and how much it costs; then, what it did
local function ai_line()
  if not alive() then
    return
  end
  local width = inner_width()
  local chunks
  local paths = staged_paths()
  local a = S.ai
  if a.state == "running" then
    local frame = FRAMES[math.floor(vim.uv.hrtime() / 1e8) % #FRAMES + 1]
    chunks = {
      { (" %s drafting… "):format(frame), "AgentStatus" },
      { ("%s · %.1fs "):format(a.model or "agent", (vim.uv.hrtime() - (a.t0 or 0)) / 1e9), "AgentHint" },
    }
  elseif a.state == "error" then
    chunks = { { " ✘ AI failed: ", "CommitErr" }, { text.clip(a.err or "unknown error", 200), "CommitErr" } }
  elseif a.state == "done" then
    local u = a.usage or {}
    chunks = { { " ✦ drafted by ", "CommitAI" }, { (a.model or "agent") .. " ", "CommitAI" } }
    local bits = { ("%.1fs"):format(a.secs or 0) }
    if u.tokens_in then
      bits[#bits + 1] = ("%s→%s tok"):format(text.tokens(u.tokens_in), text.tokens(u.tokens_out or 0))
    end
    if u.cost and u.cost > 0 then
      bits[#bits + 1] = ("$%.4f"):format(u.cost)
    end
    chunks[#chunks + 1] = { "· " .. table.concat(bits, " · ") .. " ", "AgentHint" }
    chunks[#chunks + 1] = { "· u undo · Ctrl-g redo ", "AgentHint" }
  elseif #paths == 0 then
    chunks = {
      { " ✦ AI ", "CommitAI" },
      { "· stage files first (Space in the list); the draft reads only what is staged ", "AgentHint" },
    }
  else
    local d = ai.describe(paths, S.root)
    chunks = {
      { " ✦ AI ", "CommitAI" },
      { (d.model or "no backend") .. " ", "CommitAI" },
      { "· Ctrl-g to draft ", "AgentHint" },
      {
        ("· reads %d file%s, %s%s "):format(
          d.files,
          d.files == 1 and "" or "s",
          text.tokens(d.diff_chars):gsub("k$", "k chars"):gsub("^(%d+)$", "%1 chars"),
          d.truncated and (" (cut to " .. text.tokens(d.limit) .. ")") or ""
        ),
        d.truncated and "CommitWarn" or "AgentHint",
      },
    }
  end
  -- the staged review (agent/review): the hint (first to go when the panel is narrow), running, or what it found
  local rv = S.review
  if rv and rv.state == "idle" and #paths > 0 and a.state ~= "running" and a.state ~= "error" and a.state ~= "done" then
    chunks[#chunks + 1] = { "· Ctrl-r review ", "AgentHint" }
  end
  -- its result goes right after the model (the chunks that are never trimmed): the "reads N files" estimate gives way first
  if rv and rv.state == "running" then
    table.insert(chunks, 3, { "· reviewing what is staged… ", "AgentStatus" })
  elseif rv and rv.state == "done" then
    table.insert(
      chunks,
      3,
      rv.n == 0 and { "· ✔ review: nothing found ", "CommitOk" }
        or { ("· review: %d finding%s (quickfix) "):format(rv.n, rv.n == 1 and "" or "s"), "CommitWarn" }
    )
  end
  fit(chunks, width, 3)
  -- written as text with one highlight per chunk
  local line, spans = " ", {}
  for _, c in ipairs(chunks) do
    spans[#spans + 1] = { #line, #line + #c[1], c[2] }
    line = line .. c[1]
  end
  vim.bo[S.status_buf].modifiable = true
  vim.api.nvim_buf_set_lines(S.status_buf, 0, -1, false, { line })
  vim.bo[S.status_buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(S.status_buf, NS, 0, -1)
  for _, sp in ipairs(spans) do
    vim.api.nvim_buf_set_extmark(S.status_buf, NS, 0, sp[1], { end_col = sp[2], hl_group = sp[3] })
  end
  -- placeholder when the message is empty
  local empty = #vim.api.nvim_buf_get_lines(S.msg_buf, 0, -1, false) == 1
    and (vim.api.nvim_buf_get_lines(S.msg_buf, 0, 1, false)[1] or "") == ""
  pcall(vim.api.nvim_buf_del_extmark, S.msg_buf, NS, 2)
  if empty then
    vim.api.nvim_buf_set_extmark(S.msg_buf, NS, 0, 0, {
      id = 2,
      virt_text = { { "type(scope): subject", "AgentInputPlaceholder" } },
      virt_text_pos = "overlay",
      hl_mode = "combine",
    })
  end
end

local function redraw_msg()
  chrome()
  ai_line()
end

-- ── file list ────────────────────────────────────────────────────────────────

local LETTER_HL = { A = "CommitAdd", ["?"] = "CommitAdd", D = "CommitDel", U = "CommitErr" }

--- Paints what gets committed and what does NOT; keeps the cursor on the same path
---@param keep_path string?
local function render_files(keep_path)
  local lines, marks, rows = {}, {}, {}
  local staged, other = {}, {}
  local sa, sd = 0, 0
  for _, e in ipairs(S.entries) do
    if e.staged then
      staged[#staged + 1] = e
      sa, sd = sa + (e.adds or 0), sd + (e.dels or 0)
    else
      other[#other + 1] = e
    end
  end

  local function header(label, group, hl, count_adds, count_dels)
    lines[#lines + 1] = label
    rows[#lines] = { group = group }
    marks[#lines] = { hl = hl, adds = count_adds, dels = count_dels }
  end
  local function entry_line(e)
    local dir, base = e.path:match "^(.*/)([^/]+/?)$"
    dir, base = dir or "", base or e.path
    local marker = e.staged and "●" or "○"
    local parts = {
      { marker, e.staged and "CommitStaged" or "CommitUnstaged" },
      { " ", nil },
      { e.letter, LETTER_HL[e.letter] or "CommitChanged" },
      { "  ", nil },
      { dir, "CommitDim" },
      { base, e.staged and nil or "CommitUnstaged" },
    }
    if e.partial then
      parts[#parts + 1] = { "  + edits not staged", "CommitWarn" }
    end
    local line, spans = "", {}
    for _, p in ipairs(parts) do
      if p[2] then
        spans[#spans + 1] = { #line, #line + #p[1], p[2] }
      end
      line = line .. p[1]
    end
    lines[#lines + 1] = line
    rows[#lines] = { entry = e }
    marks[#lines] = { spans = spans, adds = e.adds, dels = e.dels, new = e.untracked }
  end

  if S.amend then
    header(
      ("Staged · %d file%s will be ADDED to %s"):format(
        #staged,
        #staged == 1 and "" or "s",
        S.head and S.head.hash or "HEAD"
      ),
      "staged",
      "CommitHeader",
      sa,
      sd
    )
  else
    header(
      ("Staged · %d file%s — goes in the commit"):format(#staged, #staged == 1 and "" or "s"),
      "staged",
      "CommitHeader",
      sa,
      sd
    )
  end
  if #staged == 0 then
    lines[#lines + 1] = "nothing staged yet: Space stages the file under the cursor, a stages everything"
    rows[#lines] = {}
    marks[#lines] = { hl = "CommitDim" }
  end
  for _, e in ipairs(staged) do
    entry_line(e)
  end
  if #other > 0 then
    header(("Not staged · %d — NOT included"):format(#other), "other", "CommitHeader")
    for _, e in ipairs(other) do
      entry_line(e)
    end
  end

  S.rows, S.nlines = rows, #lines
  local buf = S.files_buf
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  for i, m in pairs(marks) do
    if m.hl then
      -- section bars run the full width of the panel (hl_eol), like the demo's blue title bars
      vim.api.nvim_buf_set_extmark(buf, NS, i - 1, 0, { end_row = i, end_col = 0, hl_group = m.hl, hl_eol = true })
    end
    for _, s in ipairs(m.spans or {}) do
      vim.api.nvim_buf_set_extmark(buf, NS, i - 1, s[1], { end_col = s[2], hl_group = s[3] })
    end
    local right = {}
    if m.new then
      right[#right + 1] = { "new", "CommitDim" }
    end
    if (m.adds or 0) > 0 then
      right[#right + 1] = { ("+%d"):format(m.adds), "CommitAdd" }
    end
    if (m.dels or 0) > 0 then
      right[#right + 1] = { (#right > 0 and " " or "") .. ("−%d"):format(m.dels), "CommitDel" }
    end
    if #right > 0 then
      vim.api.nvim_buf_set_extmark(buf, NS, i - 1, 0, { virt_text = right, virt_text_pos = "right_align" })
    end
  end

  -- cursor: same path, or the first file row
  local target
  for i, r in pairs(rows) do
    if r.entry and (keep_path == nil or r.entry.path == keep_path) and (target == nil or i < target) then
      target = i
    end
  end
  target = target or 1
  local files_cfg, msg_cfg, status_cfg = layout()
  vim.api.nvim_win_set_config(S.files_win, files_cfg)
  vim.api.nvim_win_set_config(S.msg_win, msg_cfg)
  vim.api.nvim_win_set_config(S.status_win, status_cfg)
  if vim.api.nvim_win_is_valid(S.files_win) then
    pcall(vim.api.nvim_win_set_cursor, S.files_win, { math.min(target, S.nlines), 0 })
  end
end

--- Re-reads git and repaints everything
---@param keep_path string?
local function refresh(keep_path)
  if not alive() then
    return
  end
  S.entries = git.status(S.root)
  S.branch = git.branch(S.root)
  render_files(keep_path)
  redraw_msg()
end

-- ── actions ──────────────────────────────────────────────────────────────────

local function focus(which)
  if not alive() then
    return
  end
  vim.api.nvim_set_current_win(which == "files" and S.files_win or S.msg_win)
end

local function current_row()
  return S.rows[vim.api.nvim_win_get_cursor(S.files_win)[1]]
end

---@param ok boolean
---@param err string
local function check_git(ok, err)
  if not ok then
    log.error("git: " .. text.clip(err, 300))
  end
end

local function toggle()
  local row = current_row()
  if not row then
    return
  end
  local keep
  if row.entry then
    local e = row.entry
    keep = e.path
    if e.staged and not e.partial then
      check_git(git.unstage(S.root, { e.path }))
    else
      check_git(git.stage(S.root, { e.path }))
    end
  elseif row.group == "staged" then
    check_git(git.unstage(S.root, staged_paths()))
  elseif row.group == "other" then
    check_git(git.stage(S.root, pending_paths()))
  else
    return
  end
  refresh(keep)
end

local function stage_all()
  local paths = pending_paths()
  if #paths > 0 then
    check_git(git.stage(S.root, paths))
    refresh()
  end
end

local function unstage_all()
  local paths = staged_paths()
  if #paths > 0 then
    check_git(git.unstage(S.root, paths))
    refresh()
  end
end

local function close_preview()
  if S and S.preview and vim.api.nvim_win_is_valid(S.preview) then
    vim.api.nvim_win_close(S.preview, true)
  end
  if S then
    S.preview = nil
  end
end

--- Diff of the file under the cursor in a floating window (q / Esc close it)
local function preview()
  local row = current_row()
  if not (row and row.entry) then
    return
  end
  close_preview()
  local e = row.entry
  local lines = git.diff(S.root, e)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "diff"
  vim.diagnostic.enable(false, { bufnr = buf })
  local width = math.min(vim.o.columns - 8, 120)
  local height = math.min(vim.o.lines - 8, math.max(8, #lines + 1))
  S.preview = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = require("ui.flat").border(),
    zindex = 60,
    title = (" %s · %s "):format(e.path, e.staged and "staged" or (e.untracked and "new file" or "not staged")),
    title_pos = "left",
    footer = " q close ",
    footer_pos = "center",
  })
  vim.wo[S.preview].winhighlight = WINHL
  vim.wo[S.preview].wrap = false
  local function back()
    close_preview()
    focus "files"
  end
  vim.keymap.set("n", "q", back, { buffer = buf, nowait = true, desc = "Commit close diff" })
  vim.keymap.set("n", "<Esc>", back, { buffer = buf, nowait = true, desc = "Commit close diff" })
end

local function stop_timer()
  local a = S and S.ai
  if a and a.timer then
    a.timer:stop()
    a.timer:close()
    a.timer = nil
  end
end

--- Closes everything (cancels the agent if it was working)
function M.close()
  if not S or S.closing then
    return
  end
  S.closing = true
  stop_timer()
  if S.ai.handle then
    pcall(S.ai.handle.kill, S.ai.handle, 15)
  end
  close_preview()
  for _, win in ipairs { S.files_win, S.msg_win, S.status_win } do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  S = nil
end

-- ── AI ───────────────────────────────────────────────────────────────────────

local function draft()
  if not alive() or S.ai.state == "running" or S.busy then
    return
  end
  local paths = staged_paths()
  if #paths == 0 then
    focus "files"
    return log.info "Commit: stage the files first — the AI draft reads only what is staged"
  end
  local a = S.ai
  a.state, a.t0, a.err, a.model = "running", vim.uv.hrtime(), nil, ai.model()
  a.timer = vim.uv.new_timer()
  a.timer:start(
    0,
    100,
    vim.schedule_wrap(function()
      if alive() and S.ai.state == "running" then
        ai_line()
      end
    end)
  )
  a.handle = ai.draft(paths, S.root, function(ok, result, usage)
    if not alive() then
      return
    end
    stop_timer()
    a.handle = nil
    a.secs = (vim.uv.hrtime() - a.t0) / 1e9
    if not ok then
      a.state, a.err = "error", tostring(result)
      return redraw_msg()
    end
    a.state, a.usage = "done", usage
    -- replaces the message (undo with `u`) and leaves the focus ready to review and commit
    vim.api.nvim_buf_set_lines(S.msg_buf, 0, -1, false, result --[[@as string[] ]])
    focus "msg"
    vim.cmd "stopinsert"
    pcall(vim.api.nvim_win_set_cursor, S.msg_win, { 1, 0 })
    redraw_msg()
  end)
  ai_line()
  -- with no backend, `complete` already returned the error synchronously
end

-- ── type and scope ───────────────────────────────────────────────────────────

---@param patch { type: string?, scope: string|false? }
local function rewrite_header(patch)
  local first = vim.api.nvim_buf_get_lines(S.msg_buf, 0, 1, false)[1] or ""
  vim.api.nvim_buf_set_lines(S.msg_buf, 0, 1, false, { conventional.rewrite(first, patch) })
  redraw_msg()
  focus "msg"
end

local function pick_type()
  local hint = conventional.suggest_type(staged_paths())
  local items = {}
  for _, t in ipairs(cfg().types) do
    table.insert(items, t[1] == hint and 1 or #items + 1, t)
  end
  vim.ui.select(items, {
    prompt = "Commit type",
    format_item = function(t)
      return ("%-9s %s%s"):format(t[1], t[2], t[1] == hint and "   ← suggested" or "")
    end,
  }, function(choice)
    if choice and alive() then
      rewrite_header { type = choice[1] }
      if (vim.api.nvim_buf_get_lines(S.msg_buf, 0, 1, false)[1] or ""):match ": $" then
        vim.api.nvim_win_set_cursor(S.msg_win, { 1, 1000 })
        vim.cmd "startinsert!"
      end
    end
  end)
end

local function pick_scope()
  local first = vim.api.nvim_buf_get_lines(S.msg_buf, 0, 1, false)[1] or ""
  if not conventional.split(first) then
    return log.info "Commit: pick the type first (Ctrl-t)"
  end
  local paths = #staged_paths() > 0 and staged_paths() or vim.tbl_map(function(e)
    return e.path
  end, S.entries)
  local items =
    conventional.suggest_scopes(paths, conventional.history_scopes(git.recent_subjects(S.root, cfg().history)))
  items[#items + 1] = "(no scope)"
  items[#items + 1] = "custom…"
  vim.ui.select(items, { prompt = "Scope" }, function(choice, idx)
    if not (choice and alive()) then
      return
    end
    if idx == #items then
      return vim.ui.input({ prompt = "Scope: " }, function(input)
        input = vim.trim(input or "")
        if input ~= "" and alive() then
          rewrite_header { scope = input }
        end
      end)
    end
    rewrite_header { scope = idx == #items - 1 and false or choice }
  end)
end

-- ── review of what is staged ─────────────────────────────────────────────────

local function review()
  if not alive() or S.review.state == "running" then
    return
  end
  if #staged_paths() == 0 then
    return log.warn "Nothing staged: Space stages the file under the cursor, a stages everything"
  end
  S.review = { state = "running" }
  ai_line()
  require("agent.review").run(S.root, function(result)
    if not alive() then
      return
    end
    S.review = result and { state = "done", n = #result.findings } or { state = "idle" }
    ai_line()
  end)
end

-- ── commit ───────────────────────────────────────────────────────────────────

local function submit()
  if not alive() or S.busy then
    return
  end
  local kept = vim.tbl_filter(function(l)
    return not l:match "^#"
  end, vim.api.nvim_buf_get_lines(S.msg_buf, 0, -1, false))
  local msg = vim.trim(table.concat(kept, "\n"))
  local header = vim.split(msg, "\n", { plain = true })[1]
  local _, err = conventional.parse_header(header)
  if err then
    focus "msg"
    return log.warn("Commit message: " .. err)
  end
  local paths = staged_paths()
  if #paths == 0 and not S.amend then
    focus "files"
    return log.warn "Nothing staged: Space stages the file under the cursor, a stages everything"
  end
  local amend = S.amend
  local adds, dels = 0, 0
  for _, e in ipairs(S.entries) do
    if e.staged then
      adds, dels = adds + (e.adds or 0), dels + (e.dels or 0)
    end
  end

  S.busy = amend and "amending… (hooks may take a few seconds)" or "committing… (hooks may take a few seconds)"
  local timer = vim.uv.new_timer()
  timer:start(
    0,
    100,
    vim.schedule_wrap(function()
      if alive() and S.busy then
        chrome()
      end
    end)
  )
  git.commit(S.root, msg, amend, function(ok, info)
    timer:stop()
    timer:close()
    if not alive() then
      return
    end
    S.busy = nil
    if not ok then
      chrome()
      -- the panel stays open: fix the message (or whatever the hook rejected) and retry
      return log.error("git commit failed:\n" .. text.clip(info, 600))
    end
    M.close()
    vim.cmd "silent! checktime"
    pcall(function()
      require("gitsigns").refresh()
    end)
    log.info(
      ("✔ %s %s · %d file%s +%d −%d"):format(
        amend and "Amended" or "Committed",
        info .. " " .. header,
        #paths,
        #paths == 1 and "" or "s",
        adds,
        dels
      )
    )
  end)
end

-- ── opening ──────────────────────────────────────────────────────────────────

---@param buf integer
---@param map fun(modes: string|string[], lhs: string, fn: function, desc: string)
local function bind_common(map)
  map("n", "q", M.close, "cancel")
  map("n", "<Esc>", M.close, "cancel")
  map({ "n", "i" }, "<C-g>", draft, "AI draft")
  map({ "n", "i" }, "<C-r>", review, "review staged")
  map({ "n", "i" }, "<C-s>", submit, "commit")
end

---@param opts { amend: boolean?, ai: boolean? }?
function M.open(opts)
  opts = opts or {}
  if S then
    return focus(#staged_paths() == 0 and "files" or "msg")
  end
  local root = git.root()
  if not root then
    return log.warn "Not inside a git repository"
  end
  local head
  if opts.amend then
    head = git.head(root)
    if not head then
      return log.warn "There is no commit to amend"
    end
  elseif git.run({ "status", "--porcelain" }, root) == "" then
    return log.info "Nothing to commit: the working tree is clean"
  end

  S = {
    root = root,
    amend = opts.amend == true,
    head = head,
    entries = git.status(root),
    rows = {},
    nlines = 3,
    branch = git.branch(root),
    ai = { state = "idle" },
    review = { state = "idle" },
  } --[[@as CommitState]]

  local files_cfg, msg_cfg, status_cfg = layout()
  S.files_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[S.files_buf].bufhidden = "wipe"
  vim.bo[S.files_buf].filetype = "commitfiles"
  vim.bo[S.files_buf].modifiable = false
  S.msg_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[S.msg_buf].buftype = "acwrite"
  vim.bo[S.msg_buf].bufhidden = "wipe"
  vim.bo[S.msg_buf].swapfile = false
  vim.api.nvim_buf_set_name(S.msg_buf, "commit-message-" .. S.msg_buf)
  if head then
    vim.api.nvim_buf_set_lines(S.msg_buf, 0, -1, false, vim.split(head.message, "\n", { plain = true }))
  end

  S.status_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[S.status_buf].bufhidden = "wipe"
  vim.bo[S.status_buf].filetype = "commitstatus"
  S.status_win = vim.api.nvim_open_win(S.status_buf, false, status_cfg)
  vim.wo[S.status_win].winhighlight = "NormalFloat:AgentFloat"
  S.msg_win = vim.api.nvim_open_win(S.msg_buf, false, msg_cfg)
  S.files_win = vim.api.nvim_open_win(S.files_buf, true, files_cfg)
  for _, win in ipairs { S.files_win, S.msg_win } do
    vim.wo[win].winhighlight = WINHL
    vim.wo[win].wrap = false
  end
  vim.wo[S.files_win].cursorline = true
  vim.wo[S.files_win].signcolumn = "yes:1" -- left margin
  vim.wo[S.msg_win].signcolumn = "yes:1"
  vim.wo[S.files_win].winhighlight = WINHL .. ",CursorLine:CommitCursor"
  vim.wo[S.msg_win].wrap = true
  vim.api.nvim_set_current_win(S.msg_win)
  vim.bo[S.msg_buf].filetype = "gitcommit" -- with the message window active: spelling and column 73 apply to it
  vim.wo[S.msg_win].colorcolumn = tostring(cfg().subject_max + 1)

  local function mapper(buf)
    return function(modes, lhs, fn, desc)
      vim.keymap.set(modes, lhs, fn, { buffer = buf, nowait = true, desc = "Commit " .. desc })
    end
  end
  local fmap, mmap = mapper(S.files_buf), mapper(S.msg_buf)
  bind_common(fmap)
  bind_common(mmap)
  fmap("n", "<Space>", toggle, "stage toggle")
  fmap("n", "s", toggle, "stage toggle")
  fmap("n", "a", stage_all, "stage all")
  fmap("n", "u", unstage_all, "unstage all")
  fmap("n", "p", preview, "diff preview")
  fmap("n", "<CR>", preview, "diff preview")
  fmap("n", "g", draft, "AI draft")
  fmap("n", "<Tab>", function()
    focus "msg"
  end, "go to message")
  mmap("n", "<Tab>", function()
    focus "files"
  end, "go to files")
  mmap("n", "<CR>", submit, "submit")
  mmap({ "n", "i" }, "<C-t>", pick_type, "pick type")
  mmap({ "n", "i" }, "<C-o>", pick_scope, "pick scope")

  local group = vim.api.nvim_create_augroup("CommitPanel", { clear = true })
  vim.api.nvim_create_autocmd(
    { "TextChanged", "TextChangedI" },
    { group = group, buffer = S.msg_buf, callback = redraw_msg }
  )
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    buffer = S.msg_buf,
    callback = function()
      vim.bo[S.msg_buf].modified = false
      submit()
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = { tostring(S.files_win), tostring(S.msg_win) },
    callback = function()
      -- the close arrives queued: if another panel was opened in the meantime, this is not the one to close
      local this = S
      vim.schedule(function()
        if S == this then
          M.close()
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = vim.schedule_wrap(function()
      if alive() then
        render_files()
        redraw_msg()
      end
    end),
  })

  render_files()
  redraw_msg()
  if #staged_paths() == 0 then
    focus "files"
  else
    focus "msg"
    if opts.ai then
      draft()
    elseif (vim.api.nvim_buf_get_lines(S.msg_buf, 0, 1, false)[1] or "") == "" then
      vim.cmd "startinsert"
    end
  end
end

return M
