-- ── Mentions in a user turn ─────────────────────────────────────────────────
-- Turns the text into (clean text, sections) where sections are what the model
-- receives besides the conversation. Files come from files.lua (cached, project
-- relative); @buf/@sel/@diag read the editor; #skill reads a SKILL.md body.
-- Pure parsing plus three small editor readers; no UI.
local files = require "agent.chat.files"
local chat_text = require "agent.chat.text"

local M = {}

local function max_chars()
  local c = require("core.settings").agent.chat
  return c.max_mention_chars or c.mention_chars or 12000
end

-- Backwards-compatible surface (the selector and older tests use these).
M.COMMANDS = require("agent.chat.commands").ALL
M.COMMAND_ORDER = require("agent.chat.commands").ORDER
M.candidates = require("agent.chat.commands").filter

---@param query string?
---@return string[]
function M.filter_files(query)
  return files.filter(files.list(), query)
end

M.root = files.root
M.files = files.list
M.resolve = files.resolve

---@param kind string
---@param query string
---@return table[]
function M.suggestions(kind, query)
  return require("agent.chat.suggest").all(kind, query)
end

--- Content of a file: buffer when unsaved, disk otherwise (kept for callers).
M.file_text = files.read

--- Parses `input`. Slash commands are only the first token of the line; the
--- mentions may appear anywhere.
---@param input string
---@param opts { buf?: integer }?
---@return string clean, table sections, string? slash
function M.parse(input, opts)
  opts = opts or {}
  local body = chat_text.clean(input)
  local sections = {}
  local slash = nil
  local rest = body

  local cmd = body:match "^%s*/(%w+)"
  if cmd and M.COMMANDS[cmd] then
    slash = cmd
    rest = body:gsub("^%s*/" .. cmd .. "%s*", "", 1)
  end

  -- @file mentions: paths without spaces, matched against the project list
  local special = { buf = true, sel = true, diag = true }
  for path in body:gmatch "@([%w%._%-%/]+)" do
    local resolved = not special[path] and files.resolve(path) or nil
    if resolved then
      local content = files.read(resolved)
      if content then
        sections[#sections + 1] = {
          name = "file:" .. vim.fn.fnamemodify(resolved, ":~:."),
          text = chat_text.clip(content, max_chars()),
        }
      end
    end
  end

  if body:find "@buf" then
    local buf = opts.buf or vim.api.nvim_get_current_buf()
    if vim.api.nvim_buf_is_valid(buf) then
      local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      sections[#sections + 1] = { name = "buffer", text = chat_text.clip(content, max_chars()) }
    end
  end
  if body:find "@sel" then
    local last = vim.api.nvim_buf_get_mark(0, "<")
    local first = vim.api.nvim_buf_get_mark(0, ">")
    if last[1] > 0 then
      local a, b = math.min(last[1], first[1]), math.max(last[1], first[1])
      local lines = vim.api.nvim_buf_get_lines(0, a - 1, b, false)
      sections[#sections + 1] = { name = "selection", text = chat_text.clip(table.concat(lines, "\n"), max_chars()) }
    end
  end
  if body:find "@diag" then
    local diags = vim.diagnostic.get(opts.buf or 0)
    if #diags > 0 then
      local lines = vim.tbl_map(function(d)
        return ("L%d %s (%s)"):format((d.lnum or 0) + 1, (d.message or ""):gsub("\n", " "), d.source or "")
      end, diags)
      sections[#sections + 1] = { name = "diagnostics", text = table.concat(lines, "\n") }
    end
  end

  -- every #skill mentioned (bodies are small and capped)
  local seen = {}
  for skill in body:gmatch "#([%w%-%_]+)" do
    if not seen[skill] then
      seen[skill] = true
      local ok, store = pcall(require, "skills.store")
      if ok then
        local content = store.body and store.body(skill)
        if content then
          sections[#sections + 1] = { name = "skill:" .. skill, text = chat_text.clip(content, max_chars()) }
        end
      end
    end
  end

  return chat_text.trim(rest), sections, slash
end

--- MCP servers the environment already has (opencode global config).
---@return string[]
function M.mcp_servers()
  local ok, backend = pcall(require, "agent.backends.opencode")
  if ok and backend.config then
    local cfg = backend.config() or {}
    local names = {}
    for name in pairs(cfg.mcp or {}) do
      names[#names + 1] = name
    end
    if #names == 0 then
      local dir = (vim.env.XDG_CONFIG_HOME or vim.fn.expand "~/.config") .. "/opencode"
      local f = io.open(dir .. "/opencode.jsonc", "r") or io.open(dir .. "/opencode.json", "r")
      if f then
        local raw = f:read "*a"
        f:close()
        for name in raw:gmatch '"([%w%-%_]+)"%s*:%s*%{' do
          names[#names + 1] = name
        end
      end
    end
    return names
  end
  return {}
end

return M
