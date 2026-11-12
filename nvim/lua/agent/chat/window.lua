-- Chat panel: a real right split by default (settings.agent.chat.dock = false
-- brings back the old floating partition) with a transcript block and an input
-- block, half the screen, Opencode/Claude Code shape, flat design. It can also
-- show the project's chat history (the "home") instead of a transcript.
-- ONE place reports progress (the statusline chip); hiding keeps the session alive.
local settings = require "core.settings"

local M = {}

M.transcript_buf = nil
M.input_buf = nil
M.transcript_win = nil
M.input_win = nil
M.session = nil
M.home = nil -- { root, display_root, sessions, sel, profile } while the history is shown
M.pending_text = ""
M.pending_think = ""
M.running = false
M.injected_names = nil
M.collapsed = false -- rail on the right edge (vertical "CHAT")
M.docked = false -- true while mini lives in real splits (the editor shrinks)
M.view = nil -- "mini" | "full"; nil = settings default (mini)
M.ranges = {}
M.zoom = nil
M._prev_win = nil
M.input_lines = 3 -- desired input height (starts at 3, grows to settings.agent.chat.input_height)
M.hist_idx = 0 -- 0 = the draft being written, 1.. = older user messages
M.hist_draft = ""
M.sent_text = nil -- prompt of the turn in flight (the session stores it when it settles)
M.queue = {} -- messages typed while a turn runs; sent when it settles, in order
M.run_started = nil -- hrtime of the running turn (the activity strip shows its age)

local ACTIVITY_NS = vim.api.nvim_create_namespace "chat.activity"
local activity = { timer = nil, frame = 0 }

local function chat_cfg()
  return settings.agent.chat or {}
end

local MIN_INPUT = 3 -- the composer is never thinner than this: a one-row box felt cramped

local function border()
  return require("ui.flat").border()
end

--- The left half-cell edge of the partition. Three other sides are air, so the
--- panel reads as a docked block, not as a floating box.
---@return string|table
local function partition_border()
  if not require("ui.flat").enabled() then
    return "single"
  end
  return { "", "", "", "", "", "", "", { "▐", "FlatEdge" } }
end

--- Current view: the toggle wins over the settings default, so :Chat full/mini
--- inside the panel applies at once and survives re-opens in this session.
---@return "mini"|"full"
function M.current_view()
  return M.view or (settings.agent.chat.view == "full" and "full" or "mini")
end

local layout_mod = require "agent.chat.layout"

local function layout()
  return layout_mod.geometry(chat_cfg(), vim.o.columns, vim.o.lines, M.collapsed, M.current_view(), M.input_lines)
end

local relayout -- defined after open_windows (paint may ask for a height change)
local hide_all -- defined after the history helpers (an autocmd asks for it)

--- The view the mini panel should use: the settings `dock` unless the old
--- floating partition was asked for.
---@return boolean
local function docked_here()
  return not M.collapsed and M.current_view() == "mini" and chat_cfg().dock ~= false
end

--- Placeholder for the input, by state and profile: it teaches the keys once
--- and then gets out of the way.
---@return string
local function placeholder_text()
  if M.home then
    local entry = M.home_selected()
    if entry and entry.kind == "session" then
      local title = require("agent.chat.home").title(entry.session.title)
      if vim.fn.strdisplaywidth(title) > 28 then
        title = vim.fn.strcharpart(title, 0, 27) .. "…"
      end
      return ("Enter open “%s” · or type a new message…"):format(title)
    end
    return "Type a message to start a new chat…"
  end
  if #M.queue > 0 then
    return ("%d queued · sends when the answer settles"):format(#M.queue)
  end
  local profile = require("agent.chat.profiles").of(M.session, chat_cfg().profile)
  if profile.id == "ask" then
    return "Ask about the code… (/help for commands)"
  elseif profile.id == "minimal" then
    return "Ask… (/help for commands)"
  end
  return "Describe the change… (Shift-Enter new line)"
end

--- Input placeholder (virt_text overlay like the commit panel), not a fake line.
local function paint_placeholder()
  if not (M.input_buf and vim.api.nvim_buf_is_valid(M.input_buf)) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(M.input_buf, 0, -1, false)
  local empty = #lines == 1 and (lines[1] or "") == ""
  local ns = vim.api.nvim_create_namespace "chat.placeholder"
  vim.api.nvim_buf_clear_namespace(M.input_buf, ns, 0, -1)
  if empty then
    vim.api.nvim_buf_set_extmark(M.input_buf, ns, 0, 0, {
      id = 1,
      virt_text = { { placeholder_text(), "ChatInputPlaceholder" } },
      virt_text_pos = "overlay",
      hl_mode = "combine",
    })
  end
  if M.auto_height then
    M.auto_height()
  end
end

--- Repaint the placeholder after a profile or view change.
function M.refresh_placeholder()
  paint_placeholder()
end

--- Clears the input box (used once a turn is accepted: not before, so the text
--- survives a model pick or a failed send).
function M.clear_input()
  if not (M.input_buf and vim.api.nvim_buf_is_valid(M.input_buf)) then
    return
  end
  vim.api.nvim_buf_set_lines(M.input_buf, 0, -1, false, { "" })
  M.hist_idx, M.hist_draft = 0, ""
  paint_placeholder()
end

--- Ensure buffers exist (hide on close, never wipe the transcript).
local function ensure_buffers()
  if not (M.transcript_buf and vim.api.nvim_buf_is_valid(M.transcript_buf)) then
    M.transcript_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[M.transcript_buf].bufhidden = "hide"
    vim.bo[M.transcript_buf].filetype = "leaderchat"
    vim.bo[M.transcript_buf].modifiable = false
    vim.b[M.transcript_buf].completion = false
    vim.diagnostic.enable(false, { bufnr = M.transcript_buf })
    vim.api.nvim_buf_set_name(M.transcript_buf, "Leader Chat")
  end
  if not (M.input_buf and vim.api.nvim_buf_is_valid(M.input_buf)) then
    M.input_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[M.input_buf].bufhidden = "hide"
    vim.bo[M.input_buf].filetype = "leaderchat_input"
    vim.b[M.input_buf].completion = false -- free text: no completion popup over what you type (Enter is send)
    vim.bo[M.input_buf].omnifunc = ""
    vim.bo[M.input_buf].completefunc = ""
    vim.api.nvim_buf_set_name(M.input_buf, "Leader Chat input")
    vim.api.nvim_buf_set_lines(M.input_buf, 0, -1, false, { "" })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
      buffer = M.input_buf,
      callback = paint_placeholder,
    })
  end
end

--- Is any chat window open?
---@return boolean
function M.is_open()
  return (
    M.transcript_win
    and vim.api.nvim_win_is_valid(M.transcript_win)
    and vim.api.nvim_win_get_buf(M.transcript_win) == M.transcript_buf
  ) or (M.input_win and vim.api.nvim_win_is_valid(M.input_win))
end

--- The window the chat column grows beside: the LARGEST editable window of the
--- tab (a sidebar, a terminal or a float is never the host). The chat windows
--- themselves are excluded, so a relayout can never split from the panel.
---@return integer?
local function editing_window()
  local best, best_area
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local cfg = vim.api.nvim_win_get_config(win)
      local ft = vim.bo[buf].filetype
      if
        cfg.relative == ""
        and (vim.bo[buf].buftype == "" or ft == "nvdash")
        and ft ~= "leaderchat"
        and ft ~= "leaderchat_input"
      then
        local area = vim.api.nvim_win_get_width(win) * vim.api.nvim_win_get_height(win)
        if not best_area or area > best_area then
          best, best_area = win, area
        end
      end
    end
  end
  return best
end

--- Mini in REAL splits (the default): a column on the right holding the
--- transcript (top) and the input (bottom). `w` is the text width of the
--- column; the editor keeps the rest and reflows, like a terminal opened with
--- a vertical split (Alt-V), so no code hides under the panel.
---@param w integer
---@param input_h integer
local function open_docked(w, input_h)
  local host = editing_window() or vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(host)
  vim.cmd "botright vsplit"
  local transcript = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(transcript, M.transcript_buf)
  vim.cmd "belowright split"
  local input = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(input, M.input_buf)
  M.transcript_win, M.input_win = transcript, input
  M.docked = true
  for _, win in ipairs { transcript, input } do
    vim.w[win].leader_keep = true
    vim.wo[win].winfixwidth = true
  end
  vim.wo[input].winfixheight = true
  pcall(vim.api.nvim_win_set_width, transcript, w)
  pcall(vim.api.nvim_win_set_height, input, input_h)
end

local function open_windows()
  ensure_buffers()
  M.docked = false
  local w, col, top, transcript_h, input_h, full = layout()
  local function mark_kept(win)
    vim.w[win].leader_keep = true
  end
  local function float(buf, o)
    local enter = o.enter or false
    o.enter = nil
    return vim.api.nvim_open_win(
      buf,
      enter,
      vim.tbl_extend("force", {
        relative = "editor",
        style = "minimal",
        border = full and "none" or partition_border(),
      }, o)
    )
  end

  if M.collapsed then
    M.transcript_win = float(M.transcript_buf, {
      row = top,
      col = col,
      width = w,
      height = transcript_h,
      focusable = false,
      zindex = 50,
    })
    mark_kept(M.transcript_win)
    M.input_win = nil
  elseif full then
    -- edge to edge: no border, no padding, no titles; the input glued below
    M.transcript_win = float(M.transcript_buf, {
      row = 0,
      col = 0,
      width = w,
      height = transcript_h,
      focusable = true,
      zindex = 50,
    })
    mark_kept(M.transcript_win)
    M.input_win = float(M.input_buf, {
      row = transcript_h,
      col = 0,
      width = w,
      height = input_h,
      enter = true,
      focusable = true,
      zindex = 51,
    })
    mark_kept(M.input_win)
  elseif docked_here() then
    open_docked(w, input_h)
  else
    -- the old floating partition: full height, half width, flush to the right
    -- edge, one half-cell edge on the left, a row of air between the blocks
    M.transcript_win = float(M.transcript_buf, {
      row = top,
      col = col,
      width = w,
      height = transcript_h,
      focusable = true,
      zindex = 50,
    })
    mark_kept(M.transcript_win)

    M.input_win = float(M.input_buf, {
      row = top + transcript_h + (chat_cfg().gap or 1),
      col = col,
      width = w,
      height = input_h,
      enter = true,
      focusable = true,
      zindex = 51,
    })
    mark_kept(M.input_win)
  end

  -- flat design: filled blocks, wrap, keep the cursor in the block
  for _, win in ipairs { M.transcript_win, M.input_win } do
    if win and vim.api.nvim_win_is_valid(win) then
      local wo = vim.wo[win]
      wo.wrap = true
      wo.linebreak = true
      wo.number = false
      wo.relativenumber = false
      wo.signcolumn = "no"
      wo.statuscolumn = "" -- the global diagnostic column has no place in the panel
      wo.foldcolumn = "0"
      wo.foldenable = false
      wo.spell = false
      wo.list = false
      wo.scrolloff = 0
      wo.cursorline = false
      wo.cursorcolumn = false
      wo.winbar = "" -- the global winbar is for files; a block has no chrome
      if M.docked then
        -- a real split has no border to pad with: one blank fold cell on the
        -- left and a one-column wrap margin on the right give the panel air
        wo.foldcolumn = "1"
        wo.fillchars = "eob: ,fold: ,horiz: ,vert: "
      end
      local b = vim.api.nvim_win_get_buf(win)
      vim.bo[b].wrapmargin = M.docked and 1 or 0
      vim.b[b].completion = false -- blink must not cover the chat (it would eat <CR>)
      wo.winhighlight = win == M.transcript_win
          and "NormalFloat:ChatFloat,Normal:ChatFloat,NormalNC:ChatFloat,FloatBorder:ChatBorder,FloatTitle:ChatHeader,FloatFooter:ChatMeta,EndOfBuffer:ChatFloat,WinSeparator:ChatBorder,FoldColumn:ChatFloat"
        or "NormalFloat:ChatInput,Normal:ChatInput,NormalNC:ChatInput,FloatBorder:ChatBorder,EndOfBuffer:ChatInput,WinSeparator:ChatBorder,FoldColumn:ChatInput"
    end
  end

  -- a resize re-anchors the floats to the same margin (full: back to the edges)
  vim.api.nvim_create_autocmd("VimResized", {
    group = vim.api.nvim_create_augroup("ChatResized", { clear = true }),
    callback = vim.schedule_wrap(function()
      if M.is_open() then
        relayout()
      end
    end),
  })

  -- if the user closes one of the panel's windows (:q), hide the whole panel
  local closed = { tostring(M.transcript_win) }
  if M.input_win then
    closed[#closed + 1] = tostring(M.input_win)
  end
  vim.api.nvim_create_autocmd("WinClosed", {
    group = vim.api.nvim_create_augroup("ChatClosed", { clear = true }),
    pattern = closed,
    callback = function()
      vim.schedule(function()
        local t_gone = M.transcript_win and not vim.api.nvim_win_is_valid(M.transcript_win)
        local i_gone = M.input_win and not vim.api.nvim_win_is_valid(M.input_win)
        if t_gone or i_gone then
          hide_all()
        end
      end)
    end,
  })

  -- fade the panel in (motion.lua animates opacity and a one-row rise)
  pcall(require("ui.flat.motion").enter, { M.transcript_win, M.input_win }, full and nil or 1)
  paint_placeholder()
  M.bind_keys()
  if not M.collapsed and M.input_win and vim.api.nvim_win_is_valid(M.input_win) then
    -- on a fresh open the input is empty: no popup yet; a typed "/" arms it (TextChangedI)
    pcall(require("agent.chat.completion").arm, M.input_buf, M.input_win)
  end
end

---@param keep_input boolean?
relayout = function(keep_input)
  if not M.transcript_buf or not vim.api.nvim_buf_is_valid(M.transcript_buf) then
    return
  end
  local w, col, top, transcript_h, input_h, full = layout()
  if M.collapsed then
    if M.input_win and vim.api.nvim_win_is_valid(M.input_win) then
      pcall(vim.api.nvim_win_close, M.input_win, true)
      M.input_win = nil
    end
    if M.transcript_win and vim.api.nvim_win_is_valid(M.transcript_win) then
      pcall(vim.api.nvim_win_set_config, M.transcript_win, {
        relative = "editor",
        row = top,
        col = col,
        width = w,
        height = transcript_h,
        footer = nil,
      })
    end
    return
  end
  if M.docked then
    -- real splits: the column keeps its fraction of the screen and the input
    -- its height; the editor takes the rest on its own
    local t, i = M.transcript_win, M.input_win
    if not (t and vim.api.nvim_win_is_valid(t) and i and vim.api.nvim_win_is_valid(i)) then
      return
    end
    local wo_t, wo_i = vim.wo[t], vim.wo[i]
    wo_t.winfixwidth, wo_i.winfixwidth = false, false
    pcall(vim.api.nvim_win_set_width, t, w)
    wo_t.winfixwidth, wo_i.winfixwidth = true, true
    wo_i.winfixheight = false
    pcall(vim.api.nvim_win_set_height, i, input_h)
    wo_i.winfixheight = true
    return
  end
  if M.transcript_win and vim.api.nvim_win_is_valid(M.transcript_win) then
    pcall(vim.api.nvim_win_set_config, M.transcript_win, {
      relative = "editor",
      row = full and 0 or top,
      col = full and 0 or col,
      width = w,
      height = transcript_h,
    })
  end
  local input_row = full and transcript_h or (top + transcript_h + (chat_cfg().gap or 1))
  if not M.input_win or not vim.api.nvim_win_is_valid(M.input_win) then
    if keep_input ~= false then
      open_windows()
      return
    end
    return
  end
  pcall(vim.api.nvim_win_set_config, M.input_win, {
    relative = "editor",
    row = input_row,
    col = full and 0 or col,
    width = w,
    height = input_h,
  })
end

--- Grows/shrinks the input with its content (wrapped lines included), up to
--- `settings.agent.chat.input_height`; then the transcript takes the rest.
M.auto_height = function()
  if not (M.input_buf and vim.api.nvim_buf_is_valid(M.input_buf)) then
    return
  end
  local win = M.input_win
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end
  -- the float's border/padding and the split's fold column + wrap margin are
  -- both worth two columns of wrapping width
  local width = math.max(10, vim.api.nvim_win_get_width(win) - 2)
  local lines = vim.api.nvim_buf_get_lines(M.input_buf, 0, -1, false)
  local h = require("agent.chat.input").height(lines, width, chat_cfg().input_height or 5)
  h = math.max(MIN_INPUT, h)
  if h ~= M.input_lines then
    M.input_lines = h
    if M.is_open() then
      relayout()
    end
  end
end

--- Recalls previous user messages (Up) and comes back to the draft (Down).
---@param dir integer -1 older, 1 newer
function M.history_step(dir)
  local input = require "agent.chat.input"
  local list = input.history(M.session)
  local current = table.concat(vim.api.nvim_buf_get_lines(M.input_buf, 0, -1, false), "\n")
  local text, state = input.step({ idx = M.hist_idx, draft = M.hist_draft }, list, dir, current)
  M.hist_idx, M.hist_draft = state.idx, state.draft
  vim.api.nvim_buf_set_lines(M.input_buf, 0, -1, false, vim.split(text, "\n", { plain = true }))
  paint_placeholder()
  if M.input_win and vim.api.nvim_win_is_valid(M.input_win) then
    pcall(vim.api.nvim_win_set_cursor, M.input_win, { vim.api.nvim_buf_line_count(M.input_buf), 0 })
  end
end

---@param root string
---@param opts { sel?: integer }?
function M.show_home(root, opts)
  ensure_buffers()
  local store = require "agent.chat.store"
  local sessions = store.list_for_root(root)
  local sel = opts and opts.sel
  if not sel then
    sel = #sessions > 0 and 2 or 1
    -- coming from an open chat: keep that chat selected in the history
    if M.session and M.session.id then
      for i, s in ipairs(sessions) do
        if s.id == M.session.id then
          sel = i + 1
          break
        end
      end
    end
  end
  M.home = {
    root = root,
    display_root = vim.fn.fnamemodify(root, ":~"),
    sessions = sessions,
    sel = math.max(1, math.min(sel, #sessions + 1)),
    profile = (M.session and M.session.root == root and M.session.profile) or chat_cfg().profile or "write",
  }
  if M.is_open() then
    M.draw()
    M.refresh_placeholder()
  end
end

--- Re-reads the project's sessions (after a delete or a new chat).
function M.refresh_home()
  if not M.home then
    return
  end
  M.show_home(M.home.root, { sel = M.home.sel })
end

---@return table? entry  { kind = "new" } | { kind = "session", session = … }
function M.home_selected()
  if not M.home then
    return nil
  end
  local row = M.home.sel or 1
  if row == 1 then
    return { kind = "new" }
  end
  local session = M.home.sessions[row - 1]
  if session then
    return { kind = "session", session = session, row = row }
  end
  return nil
end

--- Moves the highlight in the history. `dir` = -1 older, 1 newer.
---@param dir integer
function M.home_move(dir)
  if not M.home then
    return
  end
  M.home.sel = math.max(1, math.min((M.home.sel or 1) + dir, #M.home.sessions + 1))
  M.draw()
  M.refresh_placeholder()
  for _, r in ipairs(M.ranges or {}) do
    if r.row == M.home.sel and M.transcript_win and vim.api.nvim_win_is_valid(M.transcript_win) then
      pcall(vim.api.nvim_win_set_cursor, M.transcript_win, { r.first, 0 })
      break
    end
  end
end

--- Opens the selected history row: the "New chat" row starts one, a session
--- resumes it. Refuses while a turn runs (its stream belongs to the old chat).
function M.home_open()
  local entry = M.home_selected()
  if not entry then
    return
  end
  if M.running then
    return require("utils.log").warn "Chat: still answering (Ctrl-X stops it)"
  end
  if entry.kind == "new" then
    return require("agent.chat").new_session()
  end
  local store = require "agent.chat.store"
  local session = store.get(entry.session.id)
  if not session then
    return M.refresh_home()
  end
  M.session = session
  M.home = nil
  M.pending_text, M.pending_think, M.injected_names = "", "", nil
  store.remember(session.root, session.id)
  M.draw()
  M.refresh_placeholder()
  M.focus()
end

--- Deletes the selected session after a confirmation.
function M.home_delete()
  local entry = M.home_selected()
  if not entry or entry.kind == "new" then
    return
  end
  local session = entry.session
  if M.running and M.session and M.session.id == session.id then
    return require("utils.log").warn "Chat: still answering (Ctrl-X stops it)"
  end
  local count = #(session.messages or {})
  require("utils.modal").confirm({
    ("Delete “%s”?"):format(require("agent.chat.home").title(session.title)),
    ("%d message%s will be removed from this machine."):format(count, count == 1 and "" or "s"),
  }, { title = "Chat history", confirm = "Delete", danger = true }, function()
    require("agent.chat.store").remove(session.id)
    if M.session and M.session.id == session.id then
      M.session = nil
    end
    M.refresh_home()
  end)
end

hide_all = function()
  M.stop_activity()
  pcall(require("agent.chat.completion").hide)
  if M.zoom and M.zoom.win and vim.api.nvim_win_is_valid(M.zoom.win) then
    vim.api.nvim_win_close(M.zoom.win, true)
  end
  M.zoom = nil
  -- where the focus goes: the window the user is in when it is not the panel
  -- (a save or a session restore hides the chat without stealing it), else the
  -- one that was current when the panel opened
  local cur = vim.api.nvim_get_current_win()
  local keep = cur ~= M.transcript_win and cur ~= M.input_win and vim.api.nvim_win_is_valid(cur)
  -- clear the fields BEFORE closing: WinClosed is queued and must not hide the
  -- panel again (or steal the focus) while this one is already going away.
  -- Build the list explicitly: { input, transcript } with a nil input would stop
  -- ipairs at the first hole and leave the rail float open.
  local wins = {}
  if M.input_win then
    wins[#wins + 1] = M.input_win
  end
  if M.transcript_win then
    wins[#wins + 1] = M.transcript_win
  end
  M.transcript_win, M.input_win = nil, nil
  M.docked = false
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  if keep and vim.api.nvim_win_is_valid(cur) then
    pcall(vim.api.nvim_set_current_win, cur)
  elseif M._prev_win and vim.api.nvim_win_is_valid(M._prev_win) then
    pcall(vim.api.nvim_set_current_win, M._prev_win)
  else
    local win = editing_window()
    if win then
      pcall(vim.api.nvim_set_current_win, win)
    end
  end
  M._prev_win = nil
end

--- Hide the panel (session keeps running in the background).
function M.hide()
  hide_all()
end

--- Brings the panel forward: focuses the input (opens it if it was hidden).
function M.focus()
  if not M.is_open() then
    return M.toggle()
  end
  -- coming from the code: hiding later returns HERE, not to the window the
  -- panel was first opened from
  local cur = vim.api.nvim_get_current_win()
  if cur ~= M.input_win and cur ~= M.transcript_win and vim.api.nvim_win_is_valid(cur) then
    local buf = vim.api.nvim_win_get_buf(cur)
    if vim.bo[buf].buftype == "" or vim.bo[buf].filetype == "nvdash" then
      M._prev_win = cur
    end
  end
  if M.collapsed then
    M.collapsed = false
    hide_all()
    open_windows()
    M.draw()
  end
  if M.input_win and vim.api.nvim_win_is_valid(M.input_win) then
    vim.api.nvim_set_current_win(M.input_win)
    pcall(vim.api.nvim_win_set_cursor, M.input_win, { 1, 0 })
    vim.cmd "startinsert"
  end
end

--- Toggle: hidden → expanded, expanded → hidden, rail → expanded.
function M.toggle()
  if M.is_open() then
    if M.collapsed then
      M.collapsed = false
      hide_all()
      open_windows()
      M.draw()
      if M.input_win and vim.api.nvim_win_is_valid(M.input_win) then
        vim.api.nvim_set_current_win(M.input_win)
        vim.cmd "startinsert"
      end
    else
      M.hide()
    end
  else
    -- remember where the user was, so hiding puts them back in the code
    local cur = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(cur)
    if vim.bo[buf].buftype == "" or vim.bo[buf].filetype == "nvdash" then
      M._prev_win = cur
    end
    M.collapsed = false
    open_windows()
    M.draw()
    if M.input_win and vim.api.nvim_win_is_valid(M.input_win) then
      vim.api.nvim_set_current_win(M.input_win)
      vim.api.nvim_win_set_cursor(M.input_win, { 1, 0 })
      vim.cmd "startinsert"
    end
  end
end

--- Collapse to the right-edge rail (or expand again). <C-t> in the panel.
function M.toggle_collapse()
  if not M.is_open() then
    return M.toggle()
  end
  if M.current_view() == "full" and not M.collapsed then
    -- the rail only exists in the mini panel: collapse means going mini
    M.collapsed = false
    M.view = "mini"
    hide_all()
    open_windows()
    M.draw()
    return
  end
  M.collapsed = not M.collapsed
  if M.collapsed then
    hide_all()
    open_windows()
    M.draw()
    if M.transcript_win and vim.api.nvim_win_is_valid(M.transcript_win) then
      vim.api.nvim_set_current_win(M.transcript_win)
    end
  else
    hide_all()
    open_windows()
    M.draw()
    if M.input_win and vim.api.nvim_win_is_valid(M.input_win) then
      vim.api.nvim_set_current_win(M.input_win)
      vim.api.nvim_win_set_cursor(M.input_win, { 1, 0 })
      vim.cmd "startinsert"
    end
  end
end

--- Set the view ("mini" right panel, "full" fullscreen). Also the default for
--- the next open in this session (M.view wins over settings).
---@param view "mini"|"full"
function M.set_view(view)
  M.view = view
  if not M.is_open() then
    return
  end
  hide_all()
  open_windows()
  M.draw()
  if M.input_win and vim.api.nvim_win_is_valid(M.input_win) then
    vim.api.nvim_set_current_win(M.input_win)
    vim.api.nvim_win_set_cursor(M.input_win, { 1, 0 })
    vim.cmd "startinsert"
  end
end

--- Toggle mini <-> full. <C-f> inside the panel.
function M.toggle_view()
  M.set_view(M.current_view() == "full" and "mini" or "full")
end

--- Re-apply the settings width/view to an open panel (settings panel, chat menu).
function M.relayout()
  if M.is_open() then
    relayout(true)
  end
end

--- Redraw the transcript (called on streaming throttled, and on settle) or the
--- history home when it is showing.
function M.draw()
  if M.transcript_buf and vim.api.nvim_buf_is_valid(M.transcript_buf) then
    if M.home and not M.collapsed then
      M.ranges = require("agent.chat.render").apply_home(M.transcript_buf, M.home, { win = M.transcript_win })
    else
      M.ranges = require("agent.chat.render").apply(M.transcript_buf, M.session, {
        win = M.transcript_win,
        pending = M.pending_text,
        thinking = M.pending_think,
        injected = M.injected_names,
        rail = M.collapsed,
        running = M.running,
        profile = (M.session and M.session.profile) or chat_cfg().profile,
      })
    end
  end
  if M.running then
    M.start_activity()
    M.activity()
  else
    M.stop_activity()
  end
end

--- Stop the activity animation and clear its overlay.
function M.stop_activity()
  if activity.timer then
    pcall(activity.timer.stop, activity.timer)
    if not activity.timer:is_closing() then
      pcall(activity.timer.close, activity.timer)
    end
    activity.timer = nil
  end
  activity.frame = 0
  if M.transcript_buf and vim.api.nvim_buf_is_valid(M.transcript_buf) then
    vim.api.nvim_buf_clear_namespace(M.transcript_buf, ACTIVITY_NS, 0, -1)
  end
end

--- One activity frame: faint "Working" dots before the first token, a blinking
--- caret at the end of the streamed text after it. It only moves extmarks: the
--- transcript is not rewritten at animation speed.
function M.activity()
  local buf = M.transcript_buf
  if not (buf and vim.api.nvim_buf_is_valid(buf) and M.running and M.is_open()) then
    if buf and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, ACTIVITY_NS, 0, -1)
    end
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, ACTIVITY_NS, 0, -1)
  local count = vim.api.nvim_buf_line_count(buf)
  local waiting = (M.pending_text or "") == "" and (M.pending_think or "") == ""
  if waiting then
    -- the render always leaves a blank soft row at the end: the strip lives there
    local line = count
    local text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
    local chunks = {
      { "  Working", "ChatActivity" },
      { string.rep(".", activity.frame % 4), "ChatTyping" },
    }
    local secs = M.run_started and math.floor((vim.uv.hrtime() - M.run_started) / 1e9) or 0
    if secs >= 1 then
      chunks[#chunks + 1] = { ("  %ds"):format(secs), "ChatActivity" }
    end
    pcall(vim.api.nvim_buf_set_extmark, buf, ACTIVITY_NS, line - 1, text == "" and 0 or #text, {
      id = 1,
      virt_text = chunks,
      virt_text_pos = text == "" and "overlay" or "eol",
    })
  else
    -- the last non-empty line is the text being written: a caret that pulses
    local line = count
    while line > 1 do
      local text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
      if text ~= "" then
        break
      end
      line = line - 1
    end
    local hl = activity.frame % 2 == 0 and "ChatTyping" or "ChatActivity"
    pcall(vim.api.nvim_buf_set_extmark, buf, ACTIVITY_NS, line - 1, 0, {
      id = 1,
      virt_text = { { "▌", hl } },
      virt_text_pos = "eol",
    })
  end
end

--- Start the activity timer (idempotent; only while a turn runs with the panel open).
function M.start_activity()
  if not (M.running and M.is_open()) then
    return
  end
  if activity.timer and not activity.timer:is_closing() then
    return
  end
  activity.frame = 0
  activity.timer = assert(vim.uv.new_timer())
  activity.timer:start(
    0,
    320,
    vim.schedule_wrap(function()
      if not (M.running and M.is_open()) then
        return M.stop_activity()
      end
      activity.frame = (activity.frame + 1) % 8
      M.activity()
    end)
  )
end

--- Message whose rendered block contains `line` (1-based); nil on headers/gaps.
---@param line integer
---@return table?
function M.message_at(line)
  for _, r in ipairs(M.ranges or {}) do
    if line >= r.first and line <= r.last then
      return r.msg
    end
  end
end

--- Moves the transcript to the previous (-1) or next (1) message you sent and centers it (PageUp/PageDown).
---@param dir integer
---@return boolean moved
function M.jump_user(dir)
  if M.home or not (M.transcript_buf and vim.api.nvim_buf_is_valid(M.transcript_buf)) then
    return false
  end
  if not (M.transcript_win and vim.api.nvim_win_is_valid(M.transcript_win)) then
    return false
  end
  local line = vim.api.nvim_win_get_cursor(M.transcript_win)[1]
  local target = require("agent.chat.render").user_range(M.ranges or {}, line, dir)
  if not target then
    return false
  end
  pcall(vim.api.nvim_win_set_cursor, M.transcript_win, { target.first, 0 })
  pcall(vim.api.nvim_win_call, M.transcript_win, function()
    vim.cmd "normal! zz"
  end)
  return true
end

--- Copies the message under the cursor (transcript or fullscreen message view).
---@return boolean copied
function M.copy_message()
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local msg
  if M.zoom and M.zoom.msg then
    msg = M.zoom.msg
  elseif buf == M.transcript_buf then
    msg = M.message_at(line)
  end
  if not msg then
    return false
  end
  require("agent.ui.clipboard").copy(require("agent.chat.render").message_text(msg), msg.role or "message")
  return true
end

--- Applies the full-file blocks of the assistant message under the cursor.
--- Also the manual path when auto-apply is off or the buffer was unsaved.
---@return boolean applied
function M.apply_message()
  local msg
  if M.zoom and M.zoom.msg then
    msg = M.zoom.msg
  elseif vim.api.nvim_get_current_buf() == M.transcript_buf then
    msg = M.message_at(vim.api.nvim_win_get_cursor(0)[1])
  end
  if not msg or msg.role ~= "assistant" then
    require("utils.log").info "Chat: no assistant message on this line"
    return false
  end
  if not M.session then
    return false
  end
  local res = require("agent.chat.apply").run(M.session, msg.text)
  msg.meta = msg.meta or {}
  msg.meta.applied = res.files
  msg.meta.apply_unchanged = res.unchanged
  msg.meta.apply_skipped = res.skipped
  msg.meta.apply_errors = res.errors
  M.draw()
  if #res.files > 0 then
    require("utils.log").info(("Chat: applied %s"):format(table.concat(res.files, ", ")))
    return true
  elseif #res.errors > 0 then
    require("utils.log").warn(("Chat: not applied %s"):format(table.concat(res.errors, "; ")))
  elseif #res.unchanged > 0 then
    require("utils.log").info(("Chat: already up to date: %s"):format(table.concat(res.unchanged, ", ")))
  else
    require("utils.log").info "Chat: no full-file block to apply"
  end
  return false
end

--- Last message with `role` in the open chat (nil on the history home).
---@param role string "assistant"|"user"
---@return table?
function M.last_message(role)
  if not M.session or M.home then
    return nil
  end
  local messages = M.session.messages or {}
  for i = #messages, 1, -1 do
    local msg = messages[i]
    if msg.role == role and (msg.text or "") ~= "" then
      return msg
    end
  end
end

--- Copies the last answer (assistant) or the last prompt you sent (user) from
--- anywhere in the panel: no need to walk to the message first. Works from the
--- composer in insert mode, which is where the focus stays after sending.
---@param role string? "assistant" (default) | "user"
---@return boolean copied
function M.copy_last(role)
  role = role or "assistant"
  if M.home then
    return require("utils.log").info "Chat: open a chat first (Enter)"
  end
  -- while a turn runs its user message is not in the session yet: the last one
  -- you put is the prompt that started it
  if role == "user" and M.running and (M.sent_text or "") ~= "" then
    require("agent.ui.clipboard").copy(M.sent_text, "your last message")
    return true
  end
  local msg = M.last_message(role)
  if not msg then
    return require("utils.log").info(role == "assistant" and "Chat: no answer yet" or "Chat: nothing sent yet")
  end
  local what = role == "assistant" and "last answer" or "your last message"
  require("agent.ui.clipboard").copy(require("agent.chat.render").message_text(msg), what)
  return true
end

--- True when the composer is empty (one empty line; a placeholder is an extmark).
---@return boolean
function M.input_empty()
  if not (M.input_buf and vim.api.nvim_buf_is_valid(M.input_buf)) then
    return false
  end
  local lines = vim.api.nvim_buf_get_lines(M.input_buf, 0, -1, false)
  return #lines == 1 and lines[1] == ""
end

--- Puts `text` in the composer and focuses it (an answer chosen from a picker):
--- it is not sent, so the user can still add detail or edit it.
---@param text string
function M.set_input(text)
  if not (M.input_buf and vim.api.nvim_buf_is_valid(M.input_buf)) then
    return
  end
  vim.api.nvim_buf_set_lines(M.input_buf, 0, -1, false, vim.split(text, "\n", { plain = true }))
  M.hist_idx, M.hist_draft = 0, ""
  M.refresh_placeholder()
  M.focus()
  if M.input_win and vim.api.nvim_win_is_valid(M.input_win) then
    pcall(vim.api.nvim_win_set_cursor, M.input_win, { vim.api.nvim_buf_line_count(M.input_buf), 0 })
  end
end

--- True when the panel has the keyboard focus (input, transcript or message view).
---@return boolean
function M.focused()
  local win = vim.api.nvim_get_current_win()
  return win == M.input_win or win == M.transcript_win or (M.zoom and win == M.zoom.win) or false
end

--- The picker may open by itself only when the user is ready to answer: the
--- composer has the focus and is empty, and nothing is queued.
---@return boolean
function M.can_auto_ask()
  return chat_cfg().ask_picker ~= false
    and M.is_open()
    and not M.collapsed
    and vim.api.nvim_get_current_win() == M.input_win
    and M.input_empty()
    and #M.queue == 0
end

--- One note when a turn settles while the panel is not in front of the user.
---@param session table?
function M.notify_ready(session)
  if chat_cfg().notify == false then
    return
  end
  if M.is_open() and not M.collapsed and M.focused() then
    return
  end
  local question = require("agent.chat.ask").of(session)
  require("utils.log").info(question and "Chat: question ready" or "Chat: answer ready")
end

--- Picker over the options of the last ```ask block. A choice lands in the
--- composer (not sent), so it can be edited; "Write my own answer…" just focuses it.
function M.answer_question()
  local ask = require("agent.chat.ask").of(M.session)
  if not ask then
    return require("utils.log").info "Chat: no question to answer"
  end
  local items = {}
  for _, option in ipairs(ask.options) do
    items[#items + 1] = { label = option, value = option }
  end
  items[#items + 1] = { label = "Write my own answer…", own = true }
  local title = ask.question
  if vim.fn.strdisplaywidth(title) > 72 then
    title = vim.fn.strcharpart(title, 0, 71) .. "…"
  end
  require("agent.ui.select").pick(items, { title = "Chat · " .. title }, function(choice)
    if choice.own then
      M.focus()
    else
      M.set_input(choice.value)
    end
  end)
end

--- Queues a message typed while a turn runs; the caller clears the composer.
---@param text string
function M.enqueue(text)
  M.queue[#M.queue + 1] = text
  M.refresh_placeholder()
  require("utils.log").info(("Chat: queued (%d waiting)"):format(#M.queue))
end

---@return string? text of the oldest queued message
function M.dequeue()
  local text = table.remove(M.queue, 1)
  M.refresh_placeholder()
  return text
end

--- Copies the fenced code block under the cursor (fallback: the whole message).
---@return boolean copied
function M.copy_code_block()
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local msg, range
  if M.zoom and M.zoom.msg then
    msg = M.zoom.msg
  elseif buf == M.transcript_buf then
    for _, r in ipairs(M.ranges or {}) do
      if line >= r.first and line <= r.last then
        msg, range = r.msg, r
        break
      end
    end
  end
  if not msg then
    return false
  end
  local offset = range and (line - range.first) or 0
  local code = require("agent.chat.render").code_block_at(msg, offset)
  if code then
    require("agent.ui.clipboard").copy(code, "code block")
    return true
  end
  return M.copy_message()
end

--- "View more": the message the cursor is on, full size, markdown, `y` copies it.
---@param msg table?
function M.open_message(msg)
  if not msg then
    msg = M.message_at(vim.api.nvim_win_get_cursor(0)[1])
  end
  if not msg then
    return require("utils.log").info "Chat: no message on this line"
  end
  if M.zoom and M.zoom.win and vim.api.nvim_win_is_valid(M.zoom.win) then
    vim.api.nvim_win_close(M.zoom.win, true)
  end
  local lines = vim.split(require("agent.chat.text").clean(msg.text), "\n", { plain = true })
  local width = math.min(vim.o.columns - 8, 110)
  local height = math.min(vim.o.lines - 8, math.max(#lines + 2, 10))
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  vim.diagnostic.enable(false, { bufnr = buf })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local role = msg.role == "user" and "you" or (msg.role or "message")
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = border(),
    title = { { (" %s "):format(role), "ChatHeader" }, { " y copy · q close ", "ChatMeta" } },
    title_pos = "left",
    zindex = 70,
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].winhighlight =
    "NormalFloat:ChatFloat,Normal:ChatFloat,FloatBorder:ChatBorder,FloatTitle:ChatHeader,EndOfBuffer:ChatFloat"
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    M.zoom = nil
  end
  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true, desc = "Chat close message" })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true, desc = "Chat close message" })
  M.zoom = { win = win, msg = msg }
  vim.keymap.set("n", "y", function()
    require("agent.ui.clipboard").copy(msg.text or "", role)
  end, { buffer = buf, nowait = true, desc = "Chat copy message" })
  pcall(vim.treesitter.start, buf, "markdown")
  require("agent.chat.render").markdown(buf, win)
end

--- Buffer-local keys for the chat panel.
function M.bind_keys()
  local function map(buf, modes, lhs, rhs, desc)
    vim.keymap.set(modes, lhs, rhs, { buffer = buf, nowait = true, desc = desc })
  end
  if not (M.input_buf and vim.api.nvim_buf_is_valid(M.input_buf)) then
    return
  end
  -- input: Enter sends (Shift-Enter / Ctrl-J inserts a newline); with the slash popup open, Enter/Tab accept
  map(M.input_buf, "i", "<CR>", function()
    if require("agent.chat.completion").accept() then
      return
    end
    local text = table.concat(vim.api.nvim_buf_get_lines(M.input_buf, 0, -1, false), "\n")
    -- empty Enter on the history opens the highlighted chat instead of sending nothing
    if M.home and text:match "^%s*$" then
      vim.cmd "stopinsert"
      M.home_open()
      return
    end
    vim.cmd "stopinsert"
    -- the text is kept unless the turn is accepted (a model pick keeps it visible,
    -- then sends it by itself): chat.send clears the box when it proceeds
    local accepted = require("agent.chat").send(text)
    if accepted then
      M.clear_input()
    end
    -- keep focus in the input (the answer streams into the transcript above)
    if M.input_win and vim.api.nvim_win_is_valid(M.input_win) then
      vim.api.nvim_set_current_win(M.input_win)
      vim.cmd "startinsert"
    end
  end, "Chat send")
  map(M.input_buf, "i", "<Tab>", function()
    local completion = require "agent.chat.completion"
    if completion.is_visible() then
      completion.move(1)
    else
      if completion.accept() then
        return
      end
      vim.api.nvim_feedkeys(vim.keycode "<Tab>", "n", false)
    end
  end, "Chat complete")
  map(M.input_buf, "i", "<S-Tab>", function()
    local completion = require "agent.chat.completion"
    if completion.is_visible() then
      completion.move(-1)
    end
  end, "Chat complete prev")
  map(M.input_buf, "i", "<Down>", function()
    local completion = require "agent.chat.completion"
    local empty = #vim.api.nvim_buf_get_lines(M.input_buf, 0, -1, false) == 1
      and (vim.api.nvim_buf_get_lines(M.input_buf, 0, 1, false)[1] or "") == ""
    if completion.is_visible() then
      completion.move(1)
    elseif M.home and empty then
      M.home_move(1)
    else
      M.history_step(1) -- newer message, then the draft
    end
  end, "Chat next message")
  map(M.input_buf, "i", "<Up>", function()
    local completion = require "agent.chat.completion"
    local empty = #vim.api.nvim_buf_get_lines(M.input_buf, 0, -1, false) == 1
      and (vim.api.nvim_buf_get_lines(M.input_buf, 0, 1, false)[1] or "") == ""
    if completion.is_visible() then
      completion.move(-1)
    elseif M.home and empty then
      M.home_move(-1)
    else
      M.history_step(-1) -- older message
    end
  end, "Chat previous message")
  for key, dir in pairs { ["<PageUp>"] = -1, ["<PageDown>"] = 1 } do
    map(M.input_buf, { "n", "i" }, key, function()
      M.jump_user(dir)
    end, dir < 0 and "Chat previous sent message" or "Chat next sent message")
  end
  map(M.input_buf, "i", "<C-c>", function()
    require("agent.chat.completion").hide()
  end, "Chat complete close")
  map(M.input_buf, { "n", "i" }, "<C-j>", "<CR>", "Chat newline")
  map(M.input_buf, { "n", "i" }, "<C-n>", function()
    require("agent.chat").new_session()
  end, "Chat new session")
  map(M.input_buf, { "n", "i" }, "<C-h>", function()
    require("agent.chat").pick_session()
  end, "Chat sessions")
  map(M.input_buf, { "n", "i" }, "<C-m>", function()
    require("agent.chat").pick_model()
  end, "Chat model")
  map(M.input_buf, { "n", "i" }, "<C-e>", function()
    require("agent.chat").pick_effort()
  end, "Chat effort")
  map(M.input_buf, { "n", "i" }, "<C-p>", function()
    require("agent.chat").pick_profile()
  end, "Chat profile")
  map(M.input_buf, { "n", "i" }, "<C-a>", function()
    require("agent.chat").draft_adr()
  end, "Chat ADR")
  map(M.input_buf, { "n", "i" }, "<C-x>", function()
    require("agent.chat").stop()
  end, "Chat stop")
  -- copy the last answer / the last prompt without leaving the composer
  map(M.input_buf, { "n", "i" }, "<C-y>", function()
    M.copy_last "assistant"
  end, "Chat copy last answer")
  map(M.input_buf, { "n", "i" }, "<M-y>", function()
    M.copy_last "user"
  end, "Chat copy last message")
  map(M.input_buf, { "n", "i" }, "<M-q>", function()
    M.answer_question()
  end, "Chat answer question")
  map(M.input_buf, { "n", "i" }, "<C-t>", function()
    M.toggle_collapse()
  end, "Chat collapse")
  map(M.input_buf, { "n", "i" }, "<C-f>", function()
    M.toggle_view()
  end, "Chat mini/full")
  map(M.input_buf, { "n", "i" }, "<C-q>", function()
    M.hide()
  end, "Chat hide")
  -- while typing, the global <leader>aC would insert " aC": here it hides the panel
  map(M.input_buf, { "n", "i" }, "<leader>aC", function()
    M.hide()
  end, "Chat hide")
  map(M.input_buf, "n", "q", function() end, "Chat stays open")
  map(M.input_buf, "n", "<Esc>", function() end, "Chat stays open")
  map(M.input_buf, "i", "<Esc>", function()
    -- with the slash popup up, Esc only closes the popup; otherwise it leaves
    -- insert mode. The panel stays: hiding is Ctrl-Q / <leader>aC.
    local completion = require "agent.chat.completion"
    if completion.is_visible() then
      completion.hide()
      return
    end
    vim.cmd "stopinsert"
  end, "Chat leave insert")
  -- transcript: reading, i focuses the input; the panel only closes with Ctrl-Q / <leader>aC
  if M.transcript_buf and vim.api.nvim_buf_is_valid(M.transcript_buf) then
    map(M.transcript_buf, "n", "q", function() end, "Chat stays open")
    map(M.transcript_buf, "n", "<Esc>", function() end, "Chat stays open")
    map(M.transcript_buf, { "n", "i" }, "<C-q>", function()
      M.hide()
    end, "Chat hide")
    map(M.transcript_buf, { "n", "i" }, "<C-t>", function()
      M.toggle_collapse()
    end, "Chat collapse")
    map(M.transcript_buf, { "n", "i" }, "<C-f>", function()
      M.toggle_view()
    end, "Chat mini/full")
    map(M.transcript_buf, "n", "y", function()
      if not M.copy_message() then
        require("utils.log").info "Chat: no message on this line"
      end
    end, "Chat copy message")
    map(M.transcript_buf, { "n", "i" }, "<C-y>", function()
      M.copy_last "assistant"
    end, "Chat copy last answer")
    map(M.transcript_buf, { "n", "i" }, "<M-y>", function()
      M.copy_last "user"
    end, "Chat copy last message")
    map(M.transcript_buf, { "n", "i" }, "<M-q>", function()
      M.answer_question()
    end, "Chat answer question")
    map(M.transcript_buf, "n", "c", function()
      if not M.copy_code_block() then
        require("utils.log").info "Chat: no message on this line"
      end
    end, "Chat copy code block")
    map(M.transcript_buf, "n", "Y", function()
      require("agent.chat").export()
    end, "Chat copy transcript")
    for _, key in ipairs { "o", "<CR>" } do
      map(M.transcript_buf, "n", key, function()
        if M.home then
          return M.home_open()
        end
        M.open_message()
      end, "Chat view message")
    end
    for key, delta in pairs { j = 1, k = -1 } do
      map(M.transcript_buf, "n", key, function()
        if M.home then
          M.home_move(delta)
        else
          vim.cmd("normal! " .. key)
        end
      end, "Chat history move")
    end
    for key, dir in pairs { ["<PageUp>"] = -1, ["<PageDown>"] = 1 } do
      map(M.transcript_buf, { "n", "i" }, key, function()
        M.jump_user(dir)
      end, dir < 0 and "Chat previous sent message" or "Chat next sent message")
    end
    map(M.transcript_buf, "n", "n", function()
      if M.home then
        require("agent.chat").new_session()
      else
        vim.cmd "normal! n"
      end
    end, "Chat new session")
    map(M.transcript_buf, "n", "D", function()
      if M.home then
        M.home_delete()
      end
    end, "Chat delete session")
    map(M.transcript_buf, "n", "<2-LeftMouse>", function()
      if not M.home then
        return
      end
      local mouse = vim.fn.getmousepos()
      local row = require("agent.chat.home").row_at(M.ranges, mouse.line)
      if row then
        M.home.sel = row
        M.draw()
        M.home_open()
      end
    end, "Chat open session")
    map(M.transcript_buf, "n", "h", function()
      require("agent.chat").pick_session()
    end, "Chat sessions")
    map(M.transcript_buf, "n", "A", function()
      M.apply_message()
    end, "Chat apply files")
    map(M.transcript_buf, "n", "i", function()
      if M.collapsed then
        return M.toggle_collapse()
      end
      if M.input_win and vim.api.nvim_win_is_valid(M.input_win) then
        vim.api.nvim_set_current_win(M.input_win)
        vim.cmd "startinsert"
      end
    end, "Chat focus input")
  end
end

--- Statusline chip: ONE chip while a turn runs (empty when idle).
---@return string
function M.statusline()
  if not M.running then
    return ""
  end
  local sel = require("agent.selection").current()
  local model = (M.session and M.session.model) or (sel and sel.model) or (sel and sel.backend) or ""
  -- short name: "opencode-go/deepseek-v4.1-flash" → "deepseek-v4.1-flash"
  model = model:gsub("^[^/]+/", "")
  if vim.fn.strdisplaywidth(model) > 20 then
    model = vim.fn.strcharpart(model, 0, 19) .. "…"
  end
  local profile = require("agent.chat.profiles").of(M.session, chat_cfg().profile)
  -- plain text: the chip only exists while a turn runs, no spinner glyph
  return (" %s · %s "):format(profile.label, model ~= "" and model or "chat")
end

--- Called by chat/init when a turn starts/stops. The statusline chip keeps the
--- progress outside the panel; inside, the activity strip/caret animates.
function M.set_running(on)
  M.running = on
  if on then
    M.run_started = vim.uv.hrtime()
    M.start_activity()
  else
    M.run_started = nil
    M.stop_activity()
  end
end

return M
