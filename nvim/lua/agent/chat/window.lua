-- Chat panel: a floating panel anchored to the right edge (Opencode/Claude Code
-- shape, flat design). A transcript block and an input block, one editor row apart.
-- ONE place reports progress (the statusline chip); hiding keeps the session alive.
local settings = require "core.settings"

local M = {}

M.transcript_buf = nil
M.input_buf = nil
M.transcript_win = nil
M.input_win = nil
M.session = nil
M.pending_text = ""
M.pending_think = ""
M.running = false
M.injected_names = nil
M.collapsed = false -- rail on the right edge (vertical "CHAT")
M.view = nil -- "mini" | "full"; nil = settings default (mini)
M.ranges = {}
M.zoom = nil
M._prev_win = nil
M.input_lines = 1 -- desired input height (1 grows to settings.agent.chat.input_height)
M.hist_idx = 0 -- 0 = the draft being written, 1.. = older user messages
M.hist_draft = ""

local FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local function chat_cfg()
  return settings.agent.chat or {}
end

local function border()
  return require("ui.flat").border()
end

local function rail_width()
  return chat_cfg().rail_width or 9
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

local function title_chips(session, width)
  if not session then
    return { { " ◆ Chat ", "ChatHeader" } }
  end
  local title = session.title or "New chat"
  title = title:gsub("^%l", string.upper)
  local room = math.max(8, (width or 60) - 8)
  if vim.fn.strdisplaywidth(title) > room then
    title = vim.fn.strcharpart(title, 0, room) .. "…"
  end
  local chunks = { { " ◆ " .. title .. " ", "ChatHeader" } }
  if M.running then
    chunks[#chunks + 1] =
      { ("· %s "):format(FRAMES[math.floor(vim.uv.hrtime() / 1e8) % #FRAMES + 1]), "ChatHeaderWarn" }
  end
  return chunks
end

local relayout -- defined after open_windows (paint may ask for a height change)

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
      virt_text = { { "Type…", "ChatInputPlaceholder" } },
      virt_text_pos = "overlay",
      hl_mode = "combine",
    })
  end
  if M.auto_height then
    M.auto_height()
  end
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

local function editing_window()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local cfg = vim.api.nvim_win_get_config(win)
      if cfg.relative == "" and (vim.bo[buf].buftype == "" or vim.bo[buf].filetype == "nvdash") then
        return win
      end
    end
  end
  return nil
end

local function cfg_float(win_buf, opts)
  return vim.tbl_extend("force", {
    relative = "editor",
    style = "minimal",
    border = border(),
  }, opts)
end

local function open_windows()
  ensure_buffers()
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
        border = full and "none" or border(),
      }, o)
    )
  end

  if M.collapsed then
    M.transcript_win = float(M.transcript_buf, {
      row = top,
      col = col,
      width = w,
      height = transcript_h,
      title = { { " ◆ ", "ChatHeader" } },
      title_pos = "left",
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
  else
    M.transcript_win = float(M.transcript_buf, {
      row = top,
      col = col,
      width = w,
      height = transcript_h,
      title = title_chips(M.session, w),
      title_pos = "left",
      focusable = true,
      zindex = 50,
    })
    mark_kept(M.transcript_win)

    local input_row = top + transcript_h + 2 + (chat_cfg().gap or 1)
    M.input_win = float(M.input_buf, {
      row = input_row,
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
      local b = vim.api.nvim_win_get_buf(win)
      vim.b[b].completion = false -- blink must not cover the chat (it would eat <CR>)
      wo.winhighlight = win == M.transcript_win
          and "NormalFloat:ChatFloat,Normal:ChatFloat,FloatBorder:ChatBorder,FloatTitle:ChatHeader,FloatFooter:ChatMeta,EndOfBuffer:ChatFloat"
        or "NormalFloat:ChatInput,Normal:ChatInput,FloatBorder:ChatBorder,EndOfBuffer:ChatInput"
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

  -- if the user closes the transcript with :q, hide the whole panel
  vim.api.nvim_create_autocmd("WinClosed", {
    group = vim.api.nvim_create_augroup("ChatClosed", { clear = true }),
    pattern = { tostring(M.transcript_win) },
    callback = function()
      vim.schedule(function()
        if M.transcript_win and not vim.api.nvim_win_is_valid(M.transcript_win) then
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
        title = { { " ◆ ", "ChatHeader" } },
        footer = nil,
      })
    end
    return
  end
  if M.transcript_win and vim.api.nvim_win_is_valid(M.transcript_win) then
    pcall(vim.api.nvim_win_set_config, M.transcript_win, {
      relative = "editor",
      row = full and 0 or top,
      col = full and 0 or col,
      width = w,
      height = transcript_h,
      title = not full and title_chips(M.session, w) or nil,
    })
  end
  local input_row = full and transcript_h or (top + transcript_h + 2 + (chat_cfg().gap or 1))
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
  local width = math.max(10, vim.api.nvim_win_get_width(win) - 2)
  local lines = vim.api.nvim_buf_get_lines(M.input_buf, 0, -1, false)
  local h = require("agent.chat.input").height(lines, width, chat_cfg().input_height or 5)
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

function hide_all()
  pcall(require("agent.chat.completion").hide)
  if M.zoom and M.zoom.win and vim.api.nvim_win_is_valid(M.zoom.win) then
    vim.api.nvim_win_close(M.zoom.win, true)
  end
  M.zoom = nil
  for _, win in ipairs { M.input_win, M.transcript_win } do
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  M.transcript_win, M.input_win = nil, nil
  if M._prev_win and vim.api.nvim_win_is_valid(M._prev_win) then
    vim.api.nvim_set_current_win(M._prev_win)
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
      relayout()
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

--- Redraw the transcript (called on streaming throttled, and on settle).
function M.draw()
  if M.transcript_buf and vim.api.nvim_buf_is_valid(M.transcript_buf) then
    M.ranges = require("agent.chat.render").apply(M.transcript_buf, M.session, {
      win = M.transcript_win,
      pending = M.pending_text,
      thinking = M.pending_think,
      injected = M.injected_names,
      rail = M.collapsed,
      running = M.running,
    })
  end
  if M.transcript_win and vim.api.nvim_win_is_valid(M.transcript_win) and not M.collapsed then
    local w, _, _, _, _, full = layout()
    if not full then
      pcall(vim.api.nvim_win_set_config, M.transcript_win, {
        relative = "editor",
        title = title_chips(M.session, w),
      })
    end
  end
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
    title = { { (" ◆ %s "):format(role), "ChatHeader" }, { " y copy · q close ", "ChatMeta" } },
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
  pcall(function()
    require("render-markdown.api").render { buf = buf, win = win }
  end)
end

--- Buffer-local keys for the chat panel.
function M.bind_keys()
  local function map(buf, modes, lhs, rhs, desc)
    vim.keymap.set(modes, lhs, rhs, { buffer = buf, nowait = true, desc = desc })
  end
  if not (M.input_buf and vim.api.nvim_buf_is_valid(M.input_buf)) then
    return
  end
  -- input: ⏎ send (Shift-⏎ / Ctrl-J inserts a newline); with the slash popup open, ⏎/Tab accept
  map(M.input_buf, "i", "<CR>", function()
    if require("agent.chat.completion").accept() then
      return
    end
    vim.cmd "stopinsert"
    local text = table.concat(vim.api.nvim_buf_get_lines(M.input_buf, 0, -1, false), "\n")
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
    if completion.is_visible() then
      completion.move(1)
    else
      M.history_step(1) -- newer message, then the draft
    end
  end, "Chat next message")
  map(M.input_buf, "i", "<Up>", function()
    local completion = require "agent.chat.completion"
    if completion.is_visible() then
      completion.move(-1)
    else
      M.history_step(-1) -- older message
    end
  end, "Chat previous message")
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
  map(M.input_buf, { "n", "i" }, "<C-a>", function()
    require("agent.chat").draft_adr()
  end, "Chat ADR")
  map(M.input_buf, { "n", "i" }, "<C-x>", function()
    require("agent.chat").stop()
  end, "Chat stop")
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
  map(M.input_buf, "n", "q", function()
    M.hide()
  end, "Chat hide")
  map(M.input_buf, "n", "<Esc>", function()
    M.hide()
  end, "Chat hide (Esc)")
  map(M.input_buf, "i", "<Esc>", function()
    -- with the slash popup up, Esc only closes the popup
    local completion = require "agent.chat.completion"
    if completion.is_visible() then
      completion.hide()
      return
    end
    vim.cmd "stopinsert"
    M.hide()
  end, "Chat hide (Esc)")
  -- transcript: reading, q hides, i focuses the input
  if M.transcript_buf and vim.api.nvim_buf_is_valid(M.transcript_buf) then
    map(M.transcript_buf, "n", "q", function()
      M.hide()
    end, "Chat hide")
    map(M.transcript_buf, "n", "<Esc>", function()
      M.hide()
    end, "Chat hide (Esc)")
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
        M.open_message()
      end, "Chat view message")
    end
    map(M.transcript_buf, "n", "h", function()
      require("agent.chat").pick_session()
    end, "Chat sessions")
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
  local frame = FRAMES[math.floor(vim.uv.hrtime() / 1e8) % #FRAMES + 1]
  return (" %s %s "):format(frame, model ~= "" and model or "chat")
end

--- Called by chat/init when a turn starts/stops: the title shows the spinner and
--- the statusline chip is the single progress indicator.
function M.set_running(on)
  M.running = on
  if M.transcript_win and vim.api.nvim_win_is_valid(M.transcript_win) and not M.collapsed then
    local w, _, _, _, _, full = layout()
    if not full then
      pcall(vim.api.nvim_win_set_config, M.transcript_win, {
        relative = "editor",
        title = title_chips(M.session, w),
      })
    end
  end
end

return M
