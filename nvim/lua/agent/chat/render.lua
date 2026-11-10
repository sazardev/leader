-- ── Chat transcript rendering (pure + buffer application) ───────────────────
-- `blocks` turns a session into lines/marks/ranges without touching any window:
-- tests can assert the whole transcript. `apply` writes those lines into the
-- transcript buffer and draws the flat blocks; it never decides content.
-- Markdown is kept AS IS (fences at column 0, headings, lists, quotes), so the
-- treesitter parser and render-markdown can style it and copying is exact.
local chat_text = require "agent.chat.text"
local profiles = require "agent.chat.profiles"

local M = {}

local NS = "chat.render"

local function chat_cfg()
  return require("core.settings").agent.chat or {}
end

-- Per-buffer markdown style for the transcript: code blocks are a deep block
-- (visible inside the soft panel), with their language line, and headings are
-- bands with the flat accents. It overrides the global nofile override (which
-- is tuned for small hover/answer floats) because it is passed last.
local MD_CONFIG = {
  heading = { width = "full", left_pad = 1, right_pad = 1, border = false },
  code = {
    style = "full",
    border = "hide",
    language = true,
    language_icon = true,
    language_name = true,
    left_pad = 1,
    right_pad = 1,
    width = "full",
  },
  quote = { enabled = true },
  pipe_table = { style = "normal" },
}

--- Loads render-markdown even when no markdown file was opened yet (the chat
--- buffer's filetype is `leaderchat`, so the plugin's ft hook never fires) and
--- renders this buffer with the chat's style. Best-effort: no plugin = plain
--- markdown, never an error.
---@param buf integer
---@param win integer?
local function render_markdown(buf, win)
  pcall(function()
    if not package.loaded["render-markdown"] then
      require("lazy").load { plugins = { "render-markdown.nvim" } }
    end
    require("render-markdown.api").render {
      buf = buf,
      win = win or vim.api.nvim_get_current_win(),
      force = true,
      config = MD_CONFIG,
    }
  end)
end

--- Renders a markdown buffer with the chat's style (also used by the full-size
--- message view, so it reads exactly like the transcript).
---@param buf integer
---@param win integer?
function M.markdown(buf, win)
  render_markdown(buf, win)
end

--- Vertical rail for the collapsed panel (vertical "CHAT" tab).
---@param session table
---@param running boolean
---@return string[]
function M.rail(session, running)
  local lines = { "C", "H", "A", "T", " ", "│" }
  local sel = require("agent.selection").current()
  local backend = (session and session.backend) or (sel and sel.backend) or "?"
  lines[#lines + 1] = running and "⠹" or "●"
  lines[#lines + 1] = " "
  lines[#lines + 1] = backend:sub(1, 3)
  lines[#lines + 1] = tostring(session and session.turns or 0)
  return lines
end

--- Text of a message as it is copied (clean, no prefixes).
---@param msg table
---@return string
function M.message_text(msg)
  return chat_text.clean(msg.text)
end

--- Lines of a message (clean) as `offset` (0-based) sees them.
---@param msg table
---@return string[]
function M.source_lines(msg)
  return vim.split(chat_text.clean(msg.text), "\n", { plain = true })
end

--- Code block that contains `offset` (0-based line of the message), if any.
---@param msg table
---@param offset integer
---@return string? code
function M.code_block_at(msg, offset)
  local src = M.source_lines(msg)
  local open
  for i = 1, math.min(offset + 1, #src) do
    if src[i]:match "^%s*```" then
      open = not open and i or nil -- a closing fence before the cursor cancels it
    end
  end
  if not open then
    return nil
  end
  local closing
  for i = offset + 2, #src do
    if src[i]:match "^%s*```" then
      closing = i
      break
    end
  end
  local last = (closing or (#src + 1)) - 1
  if last < open + 1 then
    return nil
  end
  local body = {}
  for i = open + 1, last do
    body[#body + 1] = src[i]
  end
  return table.concat(body, "\n")
end

--- Options that change what is rendered, with the settings as defaults.
---@param opts table
---@return table
local function pick(value, default)
  if value ~= nil then
    return value
  end
  return default
end

--- A line that starts a markdown block (fence, heading, quote, list, ordered
--- item): adding an icon before it would break the parser, so those messages
--- start without the icon and keep their markdown pristine.
---@param line string
---@return boolean
local function structural(line)
  return line:match "^%s*```" ~= nil
    or line:match "^%s*#" ~= nil
    or line:match "^%s*>" ~= nil
    or line:match "^%s*[-*+]%s" ~= nil
    or line:match "^%s*%d+[.)]%s" ~= nil
end

local function view(opts, profile)
  local cfg = chat_cfg()
  local thinking = pick(opts.show_thinking, cfg.show_thinking ~= false)
  local tokens = pick(opts.show_tokens, cfg.show_tokens ~= false)
  local context = pick(opts.show_context, cfg.show_context ~= false)
  if profile then
    if profile.show_thinking == false then
      thinking = false
    end
    if profile.show_meta == false then
      tokens = false
      context = false
    end
  end
  return {
    thinking = thinking,
    tokens = tokens,
    context = context,
  }
end

--- Render all messages into `lines` + `marks` + `ranges`.
--- marks: { line, hl, eol?, spans? } · ranges: { first, last, msg } per message.
---@param session table
---@param opts { pending?: string, thinking?: string, injected?: string[], rail?: boolean, running?: boolean, show_thinking?: boolean, show_tokens?: boolean, show_context?: boolean }?
---@return string[] lines, table[] marks, table[] ranges
function M.blocks(session, opts)
  opts = opts or {}
  if opts.rail then
    local rail = M.rail(session, opts.running)
    local marks = {}
    for i in ipairs(rail) do
      marks[#marks + 1] = { line = i, hl = i == 1 and "ChatHeader" or "ChatMeta", eol = true }
    end
    return rail, marks, {}
  end

  local profile = profiles.get(opts.profile or session.profile or chat_cfg().profile)
  local v = view(opts, profile)
  local lines, marks, ranges = {}, {}, {}

  local function add_line(text, hl, o)
    lines[#lines + 1] = text
    if hl then
      marks[#marks + 1] = { line = #lines, hl = hl, eol = o and o.eol or false, spans = o and o.spans }
    end
  end

  -- header: a blue brand bar, the chat title, then profile · model · totals
  local sel = require("agent.selection").current()
  local backend = (session.backend or (sel and sel.backend)) or "?"
  local model = (session.model or (sel and sel.model)) or "default"
  local effort = session.effort or (sel and sel.effort)
  add_line("◆ Leader Chat", "ChatHeader", { eol = true })
  add_line("  " .. (session.title or "New chat"), "ChatTitle", { eol = true })
  local stats
  if profile.show_meta == false then
    stats = ("  %s · %s/%s%s"):format(profile.label, backend, model, effort and (" · " .. effort) or "")
  else
    stats = ("  %s · %s/%s%s · %d turn%s · %s in / %s out · $%.4f"):format(
      profile.label,
      backend,
      model,
      effort and (" · " .. effort) or "",
      session.turns or 0,
      (session.turns or 0) == 1 and "" or "s",
      chat_text.tokens(session.tokens_in or 0),
      chat_text.tokens(session.tokens_out or 0),
      session.cost or 0
    )
  end
  add_line(stats, "ChatMeta", { spans = { { 2, #profile.label, "ChatProfile" } } })
  if opts.injected and #opts.injected > 0 then
    add_line("⌗ injected: " .. table.concat(opts.injected, ", "), "ChatTool")
  end
  add_line("", nil)

  for _, msg in ipairs(session.messages) do
    local first_line = #lines + 1
    local text = chat_text.clean(msg.text)
    local parts = vim.split(text, "\n", { plain = true })

    if msg.role == "user" then
      for i, l in ipairs(parts) do
        if i == 1 and not structural(l) then
          add_line("❯ " .. l, "ChatUser", { eol = true, spans = { { 0, 2, "ChatUserIcon" } } })
        else
          add_line(l, "ChatUser", { eol = true })
        end
      end
    elseif msg.role == "assistant" then
      for i, l in ipairs(parts) do
        if i == 1 and not structural(l) then
          add_line("✦ " .. l, "ChatAssistant", { spans = { { 0, 2, "ChatAssistantIcon" } } })
        else
          add_line(l, "ChatAssistant")
        end
      end
    elseif msg.role == "thinking" then
      if v.thinking then
        for i, l in ipairs(parts) do
          add_line((i == 1 and "· " or "  ") .. l, "ChatThinking", { eol = true })
        end
      end
    elseif msg.role == "tool" then
      for i, l in ipairs(parts) do
        add_line((i == 1 and "⛭ " or "  ") .. l, "ChatTool", {
          eol = true,
          spans = i == 1 and { { 0, 2, "ChatToolIcon" } } or nil,
        })
      end
    elseif msg.role == "context" then
      if v.context then
        add_line("⌗ " .. text, "ChatMeta")
      end
    end

    -- per-turn footer: what was injected, tokens, cost, time
    if msg.role == "assistant" and msg.meta then
      local bits = {}
      if msg.meta.injected and #msg.meta.injected > 0 then
        bits[#bits + 1] = "injected " .. table.concat(msg.meta.injected, ",")
      end
      local u = msg.meta.usage
      if u then
        bits[#bits + 1] = ("%s/%s tok"):format(chat_text.tokens(u.tokens_in), chat_text.tokens(u.tokens_out))
        if u.cost then
          bits[#bits + 1] = ("$%.4f"):format(u.cost)
        end
        if u.ms then
          bits[#bits + 1] = ("%ds"):format(math.floor(u.ms / 1000))
        end
      end
      if #bits > 0 and v.tokens then
        add_line("    · " .. table.concat(bits, " · "), "ChatMeta")
      end
    end
    add_line("", nil)
    ranges[#ranges + 1] = { first = first_line, last = #lines, msg = msg }
  end

  -- streaming answer (the transcript grows while the model writes)
  if opts.thinking and opts.thinking ~= "" then
    local parts = vim.split(chat_text.clean(opts.thinking), "\n", { plain = true })
    for i, l in ipairs(parts) do
      add_line((i == 1 and "· " or "  ") .. l, "ChatThinking", { eol = true })
    end
  end
  if opts.pending and opts.pending ~= "" then
    local parts = vim.split(chat_text.clean(opts.pending), "\n", { plain = true })
    for i, l in ipairs(parts) do
      if i == 1 and not structural(l) then
        add_line("✦ " .. l, "ChatAssistant", { spans = { { 0, 2, "ChatAssistantIcon" } } })
      else
        add_line(l, "ChatAssistant")
      end
    end
  end

  return lines, marks, ranges
end

-- Backwards-compatible name (tests and callers use render.lines).
M.lines = M.blocks

--- Writes lines + marks into a buffer. No treesitter, no markdown: shared by
--- the transcript (which adds markdown afterwards) and the history home.
---@param buf integer
---@param lines string[]
---@param marks table[]
---@param opts { ns?: string, keep_cursor?: boolean, win?: integer }?
local function write(buf, lines, marks, opts)
  opts = opts or {}
  local win = opts.win or vim.api.nvim_get_current_win()
  local current = vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf
  local at_bottom = current and vim.api.nvim_win_get_cursor(win)[1] >= vim.api.nvim_buf_line_count(buf) - 1
  local cursor = current and vim.api.nvim_win_get_cursor(win) or nil
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local ns = vim.api.nvim_create_namespace(opts.ns or NS)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, m in ipairs(marks or {}) do
    for _, sp in ipairs(m.spans or {}) do
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, m.line - 1, sp[1], {
        end_col = sp[1] + sp[2],
        hl_group = sp[3],
      })
    end
    if m.eol then
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, m.line - 1, 0, {
        end_row = m.line,
        end_col = 0,
        hl_group = m.hl,
        hl_eol = true,
      })
    else
      local len = #(lines[m.line] or "")
      if len > 0 then
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, m.line - 1, 0, {
          end_row = m.line - 1,
          end_col = len,
          hl_group = m.hl,
        })
      end
    end
  end
  if current and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf and at_bottom then
    pcall(vim.api.nvim_win_set_cursor, win, { math.max(1, #lines), 0 })
  elseif current and vim.api.nvim_win_is_valid(win) and cursor and opts.keep_cursor then
    pcall(vim.api.nvim_win_set_cursor, win, { math.min(cursor[1], math.max(1, #lines)), 0 })
  end
  return win
end

--- Apply `blocks` to `buf`, keeping the cursor at the bottom when it was there.
--- Code fences get treesitter once and render-markdown when the answer settles.
---@param buf integer
---@param session table
---@param opts table?
---@return table[] ranges
function M.apply(buf, session, opts)
  if not vim.api.nvim_buf_is_valid(buf) then
    return {}
  end
  opts = opts or {}
  local lines, marks, ranges = M.blocks(session, opts)
  local win = write(buf, lines, marks, { keep_cursor = true, win = opts.win })
  if not opts.rail then
    -- render-markdown looks the parser up by filetype: register the chat as
    -- markdown without giving it the filetype (no LSP, lint or ft hooks)
    pcall(vim.treesitter.language.register, "markdown", "leaderchat")
    if not vim.b[buf].chat_treesitter then
      vim.b[buf].chat_treesitter = true
      pcall(vim.treesitter.start, buf, "markdown")
    end
    local streaming = (opts.pending and opts.pending ~= "") or (opts.thinking and opts.thinking ~= "")
    if streaming then
      -- raw markdown while the answer streams: drop the previous render and
      -- its conceallevel (the settle pass renders again)
      pcall(vim.api.nvim_buf_clear_namespace, buf, vim.api.nvim_create_namespace "render-markdown.nvim", 0, -1)
      local target = opts.win or win
      if target and vim.api.nvim_win_is_valid(target) then
        vim.wo[target].conceallevel = 0
      end
    else
      render_markdown(buf, opts.win or win)
    end
  end
  return ranges
end

--- Paints the history home (plain lines; no markdown parser).
---@param buf integer
---@param home table
---@param opts { now?: integer, win?: integer }?
---@return table[] ranges
function M.apply_home(buf, home, opts)
  if not vim.api.nvim_buf_is_valid(buf) then
    return {}
  end
  opts = opts or {}
  local lines, marks, ranges = require("agent.chat.home").lines(home, { now = opts.now })
  write(buf, lines, marks, { keep_cursor = true, win = opts.win })
  -- leave no markdown decoration from a previous transcript over the plain home
  pcall(vim.api.nvim_buf_clear_namespace, buf, vim.api.nvim_create_namespace "render-markdown.nvim", 0, -1)
  if opts.win and vim.api.nvim_win_is_valid(opts.win) then
    vim.wo[opts.win].conceallevel = 0
  end
  return ranges
end

return M
