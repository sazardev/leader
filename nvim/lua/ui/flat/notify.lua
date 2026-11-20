-- ── Flat notifications ───────────────────────────────────────────────────────
-- Replaces `vim.notify`. `settings.ui.notify` picks the shape (also in <leader>Sp, applied at once):
--   true (default) = the demo's note: a small filled block at the bottom right with a row of air above and below the
--     text, a thin colored bar down its whole left side (green info, yellow warning, red error), the leading phrase
--     bold in that color (`Session restored · 3 buffers`), fading in (ui/flat/motion.lua), stacked, fading away by itself;
--   "minimal" = one row, one word from the message (`save`, `clone`, `error`, `theme`, …) in the level's color:
--     `M.label` canonicalizes known actions, else uses the first meaningful word — the signal, not the sentence;
--   false = no toast at all: nothing pops up, messages stay in `:messages`.
-- No plugin: floats are never focused, so they never take a key. Without a UI (headless, scripts) the original
-- `vim.notify` is kept.
local M = {}

local MAX_WIDTH = 56
local ns = vim.api.nvim_create_namespace "FlatNotify"
local LEVELS = {
  [vim.log.levels.TRACE] = { hl = "FlatNotifyDebug", ms = 3000 },
  [vim.log.levels.DEBUG] = { hl = "FlatNotifyDebug", ms = 3000 },
  [vim.log.levels.INFO] = { hl = "FlatNotifyInfo", ms = 3500 },
  [vim.log.levels.WARN] = { hl = "FlatNotifyWarn", ms = 6000 },
  [vim.log.levels.ERROR] = { hl = "FlatNotifyError", ms = 8000 },
}
local WORDS = {
  [vim.log.levels.TRACE] = "debug",
  [vim.log.levels.DEBUG] = "debug",
  [vim.log.levels.INFO] = "info",
  [vim.log.levels.WARN] = "warn",
  [vim.log.levels.ERROR] = "error",
}
local MAX_LABEL = 10 -- a minimal note is a handful of cells wide, never a panel
-- Known actions → the single word shown in minimal mode. Order matters: an error wins over what it was doing.
local LABELS = {
  { "up to date", "ok" },
  { "error", "error" },
  { "failed", "error" },
  { "fail", "error" },
  { "cannot", "error" },
  { "unable", "error" },
  { "^e%d+", "error" }, -- Neovim's E5108 and friends
  { "warning", "warn" },
  { "deprecat", "warn" },
  { "written", "save" },
  { "wrote", "save" },
  { "saved", "save" },
  { "^save", "save" },
  { "updat", "update" },
  { "upgrad", "update" },
  { "install", "install" },
  { "clon", "clone" },
  { "restor", "restore" },
  { "reload", "reload" },
  { "clear", "clear" },
  { "remov", "remove" },
  { "delet", "remove" },
  { "creat", "add" },
  { "theme", "theme" },
  { "colorscheme", "theme" },
  { "session", "session" },
  { "diagnostic", "diag" },
  { "lint", "diag" },
  { "recent", "recent" },
  { "find", "find" },
  { "search", "find" },
  { "yank", "yank" },
  { "paste", "yank" },
  { "copi", "yank" },
  { "format", "format" },
  { "build", "build" },
  { "compil", "build" },
  { "test", "test" },
  { "agent", "agent" },
  { "pull", "git" },
  { "push", "git" },
  { "fetch", "git" },
  { "commit", "git" },
  { "config", "config" },
}
local GENERIC = {
  leader = true, note = true, info = true, warning = true, error = true,
  the = true, a = true, an = true, no = true, ["not"] = true, this = true,
  ["in"] = true, of = true, to = true, ["for"] = true, is = true, was = true,
}

--- One-word label for a minimal note: WHAT happened, colored by the level. Known actions are canonicalized
--- (`"file" written` → `save`, `clone failed` → `error`), otherwise the first meaningful word, capped short.
--- Pure.
---@param msg any
---@param level? integer
---@return string
function M.label(msg, level)
  local text = tostring(msg):lower()
  for _, rule in ipairs(LABELS) do
    if text:find(rule[1]) then
      return rule[2]
    end
  end
  for word in text:gmatch "%f[%w][%w%-]+" do
    if not GENERIC[word] and not word:match "^%d" then
      return (word:sub(1, MAX_LABEL):gsub("%-$", ""))
    end
  end
  return M.word(level) -- no words at all: the level is the only thing we know
end

--- The notification shape from `settings.ui.notify`. The old booleans are still understood: true = full, false = off;
--- the string "off" is accepted too, so a typo in local.lua cannot bring the toasts back.
---@return "full"|"minimal"|"off"
function M.mode()
  local value = require("core.settings").ui.notify
  if value == false or value == "off" then
    return "off"
  end
  if value == "minimal" then
    return "minimal"
  end
  return "full"
end

--- The single word minimal mode shows, by level
---@param level? integer
---@return string
function M.word(level)
  return WORDS[level or vim.log.levels.INFO] or "info"
end

local RIGHT = 0 -- flush right, aligned with Neovim's own message block under it
local GAP = 1 -- rows of editor between two notes, and between a note and the statusline

local stack = {} ---@type { win: integer, height: integer }[]
local original ---@type function

--- Word-wraps `text` to `width` display columns
---@param text string
---@param width integer
---@return string[]
local function wrap(text, width)
  local rows = {}
  for paragraph in (text .. "\n"):gmatch "(.-)\n" do
    local row = ""
    for word in paragraph:gmatch "%S+" do
      while vim.fn.strdisplaywidth(word) > width do
        if row ~= "" then
          rows[#rows + 1] = row
          row = ""
        end
        rows[#rows + 1] = vim.fn.strcharpart(word, 0, width)
        word = vim.fn.strcharpart(word, width)
      end
      if row == "" then
        row = word
      elseif vim.fn.strdisplaywidth(row .. " " .. word) <= width then
        row = row .. " " .. word
      else
        rows[#rows + 1] = row
        row = word
      end
    end
    rows[#rows + 1] = row
  end
  return rows
end

--- Rows taken at the bottom right by Neovim's own message window (ui/flat `messages`), if it is showing
---@return integer
local function message_rows()
  local ui2 = package.loaded["vim._core.ui2"]
  local win = ui2 and ui2.wins and ui2.wins.msg
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return 0
  end
  local c = vim.api.nvim_win_get_config(win)
  if c.hide then
    return 0
  end
  local border = type(c.border) == "table" and 1 or 0 -- our flat border adds the gap row under it
  return vim.api.nvim_win_get_height(win) + border
end

local placed = {} ---@type table<integer, integer> row each note was last put at (skip no-op moves)
local follow ---@type uv.uv_timer_t?

--- Puts every live notification in its place: from the bottom up, above the statusline and above Neovim's own
--- message window when it shows (both live in this corner)
local function layout()
  local live = {}
  for _, n in ipairs(stack) do
    if vim.api.nvim_win_is_valid(n.win) then
      live[#live + 1] = n
    else
      placed[n.win] = nil
    end
  end
  stack = live
  -- bottom edge: one row of editor above the statusline (soft on soft would merge them)
  local row = vim.o.lines - 1 - GAP - message_rows()
  for i = #stack, 1, -1 do
    local n = stack[i]
    if placed[n.win] ~= row then
      placed[n.win] = row
      vim.api.nvim_win_set_config(n.win, { relative = "editor", anchor = "SE", row = row, col = vim.o.columns - RIGHT })
    end
    row = row - n.height - GAP
  end
  -- while notes are up, follow the message window (it comes and goes on its own)
  if #stack > 0 and not follow then
    follow = vim.uv.new_timer()
    follow:start(150, 150, vim.schedule_wrap(layout))
  elseif #stack == 0 and follow then
    follow:stop()
    follow:close()
    follow = nil
  end
end

local function close(win)
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
  layout()
end

--- Fades `win` out in a few steps, then `done` (the fade-in is ui/flat/motion.lua's)
---@param win integer
---@param from integer
---@param to integer
---@param done? fun()
local function fade(win, from, to, done)
  local steps, step = 5, 0
  local timer = vim.uv.new_timer()
  timer:start(
    0,
    22,
    vim.schedule_wrap(function()
      step = step + 1
      if not vim.api.nvim_win_is_valid(win) then
        timer:stop()
        timer:close()
        return
      end
      vim.wo[win].winblend = math.floor(from + (to - from) * step / steps)
      pcall(vim.api.nvim__redraw, { flush = true }) -- also while a menu waits for a key (it does not redraw)
      if step >= steps then
        timer:stop()
        timer:close()
        if done then
          done()
        end
      end
    end)
  )
end

---@param msg any
---@param level? integer
---@param opts? { title?: string, timeout?: integer }
function M.notify(msg, level, opts)
  if #vim.api.nvim_list_uis() == 0 then
    return original(msg, level, opts)
  end
  if vim.in_fast_event() then
    return vim.schedule(function()
      M.notify(msg, level, opts)
    end)
  end
  local mode = M.mode()
  if mode == "off" then
    return original and original(msg, level, opts) -- no toast: Neovim's own messages keep working
  end
  opts = opts or {}
  local kind = LEVELS[level or vim.log.levels.INFO] or LEVELS[vim.log.levels.INFO]
  local text = tostring(msg)
  if opts.title then
    text = opts.title .. " · " .. text
  end
  -- the same note again (saving twice, a repeated warning): the one on screen stays longer, no copies stack up
  local key = kind.hl .. "\0" .. text
  for _, n in ipairs(stack) do
    if n.key == key and vim.api.nvim_win_is_valid(n.win) and not n.leaving then
      n.expire(opts.timeout or kind.ms)
      return
    end
  end
  local word = M.label(text, level)
  local rows, lead, width
  if mode == "minimal" then
    -- just the bar and one descriptive word: no wrap, no air rows, no lead phrase (a few cells, never a panel)
    rows = { "▎ " .. word .. " " }
    width = vim.fn.strdisplaywidth(rows[1])
  else
    rows = wrap(text, MAX_WIDTH)
    -- the lead: up to the first " · " (or the whole first row), bold in the level's color
    lead = #(rows[1]:match "^(.-) · " or rows[1])
    width = 0
    for i, r in ipairs(rows) do
      rows[i] = "▎ " .. r .. "  " -- the bar, then air on both sides of the text (the demo's 14px)
      width = math.max(width, vim.fn.strdisplaywidth(rows[i]))
    end
    -- a row of air above and below the text, full rows so the bar runs the whole height of the block (half-cell
    -- rows cannot carry a thin bar: it would stop halfway)
    local air = "▎" .. (" "):rep(width - 1)
    table.insert(rows, 1, air)
    rows[#rows + 1] = air
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, rows)
  local ok, win = pcall(vim.api.nvim_open_win, buf, false, {
    relative = "editor",
    anchor = "SE",
    row = vim.o.lines - 1 - GAP,
    col = vim.o.columns - RIGHT,
    width = width,
    height = #rows,
    style = "minimal",
    border = "none",
    focusable = false,
    noautocmd = true,
    zindex = 250,
  })
  if not ok then
    return original(msg, level, opts)
  end
  vim.wo[win].winhighlight = "NormalFloat:FlatNotify"
  local bar = #"▎"
  for i = 0, #rows - 1 do
    vim.api.nvim_buf_set_extmark(buf, ns, i, 0, { end_col = bar, hl_group = kind.hl })
  end
  if mode == "minimal" then
    vim.api.nvim_buf_set_extmark(buf, ns, 0, bar + 1, { end_col = bar + 1 + #word, hl_group = kind.hl .. "Lead" })
  else
    vim.api.nvim_buf_set_extmark(buf, ns, 1, bar + 1, { end_col = bar + 1 + lead, hl_group = kind.hl .. "Lead" })
  end
  local entry = { win = win, height = #rows, key = key }
  local timer = assert(vim.uv.new_timer())
  --- (re)starts the countdown; when it ends the note fades out and closes
  function entry.expire(ms)
    timer:stop()
    timer:start(
      ms,
      0,
      vim.schedule_wrap(function()
        entry.leaving = true
        timer:close()
        fade(win, 0, 100, function()
          close(win)
        end)
      end)
    )
  end
  stack[#stack + 1] = entry
  layout()
  require("ui.flat.motion").enter { win }
  entry.expire(opts.timeout or kind.ms)
end

-- Neovim's message kinds (`:h ui-messages`) → note level
local MSG_LEVELS = {
  emsg = vim.log.levels.ERROR,
  echoerr = vim.log.levels.ERROR,
  lua_error = vim.log.levels.ERROR,
  rpc_error = vim.log.levels.ERROR,
  wmsg = vim.log.levels.WARN,
}
-- kinds that are not notes: prompts, the cmdline's own echo, search feedback, listings that need the pager
local MSG_SKIP = {
  confirm = true,
  confirm_sub = true,
  return_prompt = true,
  search_cmd = true,
  search_count = true,
  empty = true,
  wildlist = true,
  completion = true,
  list_cmd = true,
  shell_out = true,
  shell_err = true,
  shell_ret = true,
  verbose = true,
  shell_cmd = true, -- the `:!cmd` echo: its output follows
}
local pending_progress ---@type string?
local progress_timer ---@type uv.uv_timer_t?
local MAX_MESSAGE_ROWS = 4 -- longer messages stay in Neovim's own window (and `g<` pages them)

--- Takes one of Neovim's own messages (through its message UI) as a note when it reads like one: short, not a
--- prompt, not a listing. Returns false to let Neovim show it.
---@param kind string
---@param content [integer, string, integer][]
---@return boolean shown
function M.message(kind, content)
  if MSG_SKIP[kind] then
    return false
  end
  local parts = {}
  for _, chunk in ipairs(content) do
    parts[#parts + 1] = chunk[2]
  end
  local text = vim.trim(table.concat(parts))
  if text == "" or select(2, text:gsub("\n", "")) >= MAX_MESSAGE_ROWS then
    return false
  end
  if M.mode() == "off" then
    return true -- consume it so Neovim's message window does not pop up either; it stays in `:messages`
  end
  if kind == "progress" then
    -- progress comes in steps (`"file"`, then `"file" 8L, 111B written`): one note with the last one
    pending_progress = text
    progress_timer = progress_timer or assert(vim.uv.new_timer())
    progress_timer:stop()
    progress_timer:start(
      60,
      0,
      vim.schedule_wrap(function()
        if pending_progress then
          M.notify(pending_progress, vim.log.levels.INFO)
          pending_progress = nil
        end
      end)
    )
    return true
  end
  M.notify(text, MSG_LEVELS[kind] or vim.log.levels.INFO)
  return true
end

--- Closes the progress notes (`Repository: checking…`): what they announced is on screen now
function M.close_progress()
  for _, n in ipairs(stack) do
    if n.key and n.key:sub(-#"…") == "…" and vim.api.nvim_win_is_valid(n.win) then
      vim.api.nvim_win_close(n.win, true)
    end
  end
  layout()
end

--- Closes every notification
function M.dismiss()
  for _, n in ipairs(stack) do
    if vim.api.nvim_win_is_valid(n.win) then
      vim.api.nvim_win_close(n.win, true)
    end
  end
  stack = {}
  layout() -- also stops the follow timer that watched Neovim's message window
end

function M.setup()
  if original then
    return
  end
  original = vim.notify
  vim.notify = M.notify
  vim.api.nvim_create_autocmd("VimResized", {
    group = vim.api.nvim_create_augroup("FlatNotify", { clear = true }),
    callback = layout,
  })
end

return M
