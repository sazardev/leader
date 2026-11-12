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
  -- the plugin is OFF by default for normal *.md files (plain source);
  -- the transcript opts back in per buffer (passed last, wins over everything)
  enabled = true,
  heading = { width = "full", left_pad = 1, right_pad = 1, border = false, icons = { "", "", "", "", "", "" } },
  code = {
    style = "full",
    border = "hide",
    language = true,
    language_icon = false,
    language_name = true,
    left_pad = 1,
    right_pad = 1,
    width = "full",
  },
  -- no pictograms in the conversation: the markdown source (-, [ ], ---) stays
  -- visible and the flat design carries the hierarchy with color and air
  bullet = { enabled = false },
  checkbox = { enabled = false },
  dash = { enabled = false },
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

--- Vertical rail for the collapsed panel (vertical "CHAT" tab). Plain text: the
--- transcript and the statusline carry the state, the rail only names the panel.
---@param session table
---@param running boolean
---@return string[]
function M.rail(session, running)
  local lines = { "C", "H", "A", "T", " " }
  local sel = require("agent.selection").current()
  local backend = (session and session.backend) or (sel and sel.backend) or "?"
  lines[#lines + 1] = backend:sub(1, 3)
  lines[#lines + 1] = tostring(session and session.turns or 0)
  if running then
    lines[#lines + 1] = "run"
  end
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

--- A `lang: path` fence is the apply convention, not a treesitter language:
--- the transcript shows `lang` so the parser/injection highlights the code;
--- copying and applying still read the original message text.
---@param line string
---@return string
local function display_fence(line)
  local prefix, lang = line:match "^(%s*```%s*)([%w%+%._%-]+):%s*[^%s].*$"
  if prefix and lang ~= "" then
    return prefix .. lang
  end
  local prefix, info = line:match "^(%s*```%s*)([^%s]+)%s*$"
  if info and info:find "[/%.]" then
    return prefix
  end
  return line
end

-- Common first words of a terminal block. Used only for an UNLABELED fence, so
-- an old answer that wrote its commands without a language still gets bash color.
local SHELL = {}
for _, word in ipairs {
  "sudo",
  "go",
  "npm",
  "pnpm",
  "yarn",
  "bun",
  "cargo",
  "make",
  "docker",
  "git",
  "curl",
  "wget",
  "python",
  "python3",
  "pip",
  "pip3",
  "uv",
  "dotnet",
  "flutter",
  "dart",
  "swift",
  "node",
  "npx",
  "deno",
  "just",
  "task",
  "kubectl",
  "terraform",
  "aws",
  "gcloud",
  "systemctl",
  "ls",
  "cd",
  "mkdir",
  "rm",
  "cp",
  "mv",
  "cat",
  "echo",
  "brew",
  "apt",
  "apt-get",
  "pacman",
  "yum",
  "dnf",
  "zypper",
  "apk",
  "chmod",
  "chown",
  "export",
  "source",
  "printf",
  "sed",
  "awk",
  "grep",
  "rg",
  "find",
  "jq",
  "yq",
  "psql",
  "sqlite3",
  "redis-cli",
} do
  SHELL[word] = true
end

---@param line string?
---@return string?
local function infer_language(line)
  if not line then
    return nil
  end
  if line:match "^%s*[%$>] " then
    return "bash"
  end
  local word = line:match "^%s*([%w_%-%.]+)"
  if word and SHELL[word] then
    return "bash"
  end
  return nil
end

--- Display form of a message's lines: parser-friendly fences (`go: path` → `go`)
--- and a bash hint for an unlabeled terminal block. Copy still uses the source.
---@param parts string[]
---@return string[]
local function display_lines(parts)
  local out = {}
  local i = 1
  while i <= #parts do
    local line = parts[i]
    local prefix, info = line:match "^(%s*```%s*)(.-)%s*$"
    if prefix and info == "ask" then
      -- the question is answered with a picker (chat/ask): show its content as a
      -- quote, never as code, and keep the source (copy) untouched
      out[#out + 1] = ""
      local j = i + 1
      while j <= #parts and not parts[j]:match "^%s*```%s*$" do
        out[#out + 1] = "> " .. parts[j]
        j = j + 1
      end
      out[#out + 1] = ""
      i = j
    elseif prefix and info == "" then
      local first
      local j = i + 1
      while j <= #parts do
        if parts[j]:match "^%s*```%s*$" then
          break
        end
        if parts[j]:find "%S" then
          first = parts[j]
          break
        end
        j = j + 1
      end
      local lang = infer_language(first)
      out[#out + 1] = lang and (prefix .. lang) or line
    else
      out[#out + 1] = display_fence(line)
    end
    i = i + 1
  end
  return out
end

--- A row of the reference block: the token in the yellow key color, its
--- description faint. Plain text only (no icons), aligned to a fixed column.
---@param add_line fun(text: string, hl: string?, o: table?)
---@param key string
---@param text string
local function hint(add_line, key, text)
  local pad = math.max(1, 14 - #key)
  add_line("  " .. key .. string.rep(" ", pad) .. text, "ChatMeta", {
    spans = { { 2, #key, "ChatHomeIcon" } },
  })
end

--- What an empty chat shows instead of a blank transcript: how to send and the
--- commands/mentions that make the panel understandable without opening /help.
---@param add_line fun(text: string, hl: string?, o: table?)
local function welcome(add_line)
  add_line("  Type a message below and press Enter.", "ChatHomeHint")
  add_line("  Write mode writes full files tagged with their path.", "ChatMeta")
  add_line ""
  add_line("  COMMANDS", "ChatSection")
  hint(add_line, "/help", "all commands")
  hint(add_line, "/new", "new chat")
  hint(add_line, "/history", "previous chats")
  hint(add_line, "/model", "model")
  hint(add_line, "/profile", "profile")
  hint(add_line, "/full", "full screen")
  hint(add_line, "/mini", "half split")
  add_line ""
  add_line("  MENTIONS", "ChatSection")
  hint(add_line, "@file", "add a file")
  hint(add_line, "@buf, @sel", "buffer and selection")
  hint(add_line, "@diag", "diagnostics")
  hint(add_line, "#skill", "a skill or $mcp MCP")
  add_line ""
  add_line("  KEYS", "ChatSection")
  hint(add_line, "Enter", "send · Shift-Enter newline")
  hint(add_line, "Ctrl-Q", "hide")
  hint(add_line, "Up / Down", "previous messages")
  hint(add_line, "Ctrl-Y", "copy the last answer")
  hint(add_line, "Alt-Y", "copy your last message")
  hint(add_line, "Alt-Q", "answer its question")
  hint(add_line, "A", "apply the files of a message")
  add_line ""
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
  add_line("", nil) -- a row of air above the bar: the block starts soft, not flush
  local sel = require("agent.selection").current()
  local model = (session.model or (sel and sel.model)) or "default"
  local effort = session.effort or (sel and sel.effort)
  add_line("  Leader Chat", "ChatHeader", { eol = true })
  add_line("  " .. (session.title or "New chat"), "ChatTitle", { eol = true })
  -- short model id (drop the provider prefix) so the header stays on one line
  -- in the half split; the totals get their own row
  local short = model:gsub("^[^/]+/", "")
  if vim.fn.strdisplaywidth(short) > 24 then
    short = vim.fn.strcharpart(short, 0, 23) .. "…"
  end
  add_line(
    ("  %s · %s%s"):format(profile.label, short, effort and (" · " .. effort) or ""),
    "ChatMeta",
    { spans = { { 2, #profile.label, "ChatProfile" } } }
  )
  if profile.show_meta ~= false then
    add_line(
      ("  %d turn%s · %s in / %s out · $%.4f"):format(
        session.turns or 0,
        (session.turns or 0) == 1 and "" or "s",
        chat_text.tokens(session.tokens_in or 0),
        chat_text.tokens(session.tokens_out or 0),
        session.cost or 0
      ),
      "ChatMeta"
    )
  end
  if opts.injected and #opts.injected > 0 then
    add_line("injected: " .. table.concat(opts.injected, ", "), "ChatTool")
  end
  add_line("", nil)

  -- no conversation yet: teach the commands instead of leaving the block blank
  local empty = #(session.messages or {}) == 0
    and not (opts.pending and opts.pending ~= "")
    and not (opts.thinking and opts.thinking ~= "")
  if empty then
    welcome(add_line)
    return lines, marks, ranges
  end

  -- Alt-Q answers the LAST answer's question: only that message carries the hint
  local last_assistant
  for i = #(session.messages or {}), 1, -1 do
    if session.messages[i].role == "assistant" then
      last_assistant = session.messages[i]
      break
    end
  end

  for _, msg in ipairs(session.messages) do
    local first_line = #lines + 1
    local text = chat_text.clean(msg.text)
    local parts = vim.split(text, "\n", { plain = true })

    if msg.role == "user" then
      -- the user turn is a filled bubble: one row of air inside it on each
      -- side, so text never touches the block's edges
      add_line("", "ChatUser", { eol = true })
      for _, l in ipairs(display_lines(parts)) do
        add_line(l, "ChatUser", { eol = true })
      end
      add_line("", "ChatUser", { eol = true })
    elseif msg.role == "assistant" then
      for _, l in ipairs(display_lines(parts)) do
        add_line(l, "ChatAssistant")
      end
      -- the question itself stays in the transcript: a hint, not a modal, so
      -- reading is never interrupted (the picker is Alt-Q, auto-opened only
      -- when the composer has the focus and is empty)
      if msg == last_assistant and require("agent.chat.ask").parse(text) then
        add_line("    Alt-Q answers with a picker · or type your own", "ChatMeta")
      end
    elseif msg.role == "thinking" then
      if v.thinking then
        for _, l in ipairs(display_lines(parts)) do
          add_line(l, "ChatThinking", { eol = true })
        end
      end
    elseif msg.role == "tool" then
      for _, l in ipairs(display_lines(parts)) do
        add_line(l, "ChatTool", { eol = true })
      end
    elseif msg.role == "context" then
      if v.context then
        add_line(text, "ChatMeta")
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
        add_line("    " .. table.concat(bits, " · "), "ChatMeta")
      end
      if v.tokens and msg.meta.history_dropped and msg.meta.history_dropped > 0 then
        add_line(
          ("    history: oldest %s chars not sent"):format(chat_text.tokens(msg.meta.history_dropped)),
          "ChatMeta"
        )
      end
      if msg.meta.applied and #msg.meta.applied > 0 then
        add_line("    applied " .. table.concat(msg.meta.applied, ", "), "ChatApplied")
      end
      if msg.meta.apply_errors and #msg.meta.apply_errors > 0 then
        add_line("    not applied " .. table.concat(msg.meta.apply_errors, "; "), "ChatApplyError")
      end
      if msg.meta.apply_unchanged and #msg.meta.apply_unchanged > 0 then
        add_line("    unchanged " .. table.concat(msg.meta.apply_unchanged, ", "), "ChatMeta")
      end
      if msg.meta.apply_skipped and #msg.meta.apply_skipped > 0 then
        add_line("    skipped " .. table.concat(msg.meta.apply_skipped, "; "), "ChatMeta")
      end
    end
    -- a soft row after every turn: separation, and the place the activity strip
    -- lives while the answer has not started yet
    add_line("", nil)
    ranges[#ranges + 1] = { first = first_line, last = #lines, msg = msg }
  end

  -- streaming answer (the transcript grows while the model writes)
  if opts.thinking and opts.thinking ~= "" then
    local parts = vim.split(chat_text.clean(opts.thinking), "\n", { plain = true })
    for _, l in ipairs(display_lines(parts)) do
      add_line(l, "ChatThinking", { eol = true })
    end
  end
  if opts.pending and opts.pending ~= "" then
    local parts = vim.split(chat_text.clean(opts.pending), "\n", { plain = true })
    for _, l in ipairs(display_lines(parts)) do
      add_line(l, "ChatAssistant")
    end
  end

  return lines, marks, ranges
end

-- Backwards-compatible name (tests and callers use render.lines).
M.lines = M.blocks

--- The message you sent above (-1) or below (1) `line`, for PageUp/PageDown.
---@param ranges { first: integer, last: integer, msg: table }[]
---@param line integer
---@param dir integer
---@return table?
function M.user_range(ranges, line, dir)
  if dir < 0 then
    for i = #ranges, 1, -1 do
      local r = ranges[i]
      if r.msg and r.msg.role == "user" and r.last < line then
        return r
      end
    end
  else
    for _, r in ipairs(ranges) do
      if r.msg and r.msg.role == "user" and r.first > line then
        return r
      end
    end
  end
end

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
        priority = 20, -- a token (yellow key, role) wins over the line's surface
      })
    end
    if m.eol then
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, m.line - 1, 0, {
        end_row = m.line,
        end_col = 0,
        hl_group = m.hl,
        hl_eol = true,
        -- below treesitter (100): the line paints the surface, the parser paints
        -- the syntax on top of it
        priority = 10,
      })
    else
      local len = #(lines[m.line] or "")
      if len > 0 then
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, m.line - 1, 0, {
          end_row = m.line - 1,
          end_col = len,
          hl_group = m.hl,
          priority = 10,
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
