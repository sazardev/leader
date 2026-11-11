-- ── Context the model asks for (@need:) ─────────────────────────────────────
-- The prompt tells every profile: when a file you do not have is missing, add a
-- line `@need: path/one, path/two` (project-relative). This module reads that
-- line from the LAST assistant answer and returns those files as sections for
-- the NEXT turn (exactly once), so "name it and Leader injects it" is true.
-- No UI here: the chat's injected disclosure shows the sections like any @file.
local M = {}

M.MAX_FILES = 5

---@param path string
---@param root string
---@return boolean
local function inside(path, root)
  path, root = vim.fs.normalize(path), vim.fs.normalize(root)
  return path == root or vim.startswith(path, root .. "/")
end

--- Paths requested by `text`, in order, without repeats.
---@param text string?
---@return string[]
function M.parse(text)
  local out, seen = {}, {}
  for line in (text or ""):gmatch "[^\n]+" do
    local list = line:match "^%s*@need:%s*(.-)%s*$"
    if list then
      for path in list:gmatch "[^,;%s]+" do
        path = path:gsub("^[`'\"]+", ""):gsub("[`'\"]+$", ""):gsub("^%.%/", "")
        if path ~= "" and not seen[path] then
          seen[path] = true
          out[#out + 1] = path
        end
      end
    end
  end
  return out
end

--- Resolves a project-relative (or absolute, inside the root) path.
---@param root string
---@param path string
---@return string?
local function resolve(root, path)
  local candidates = { path }
  if path:sub(1, 1) ~= "/" then
    candidates[2] = root .. "/" .. path
  end
  for _, candidate in ipairs(candidates) do
    local full = vim.fs.normalize(candidate)
    if inside(full, root) and vim.fn.filereadable(full) == 1 then
      return full
    end
  end
end

--- Sections for the files the LAST assistant answer asked for. Empty when
--- there is nothing to add, the request was already used, or `auto_need` is off.
--- The request is not marked here: `mark` runs when the turn really proceeds,
--- so a guard that cancels does not consume it.
---@param session table?
---@return { name: string, text: string }[]
function M.collect(session)
  local cfg = require("core.settings").agent.chat
  if cfg.auto_need == false or not session then
    return {}
  end
  local messages = session.messages or {}
  local msg
  for i = #messages, 1, -1 do
    if messages[i].role == "assistant" then
      msg = messages[i]
      break
    end
  end
  if not msg or (msg.meta and msg.meta.needs_used) then
    return {}
  end
  local paths = M.parse(msg.text)
  if #paths == 0 then
    return {}
  end
  local root = vim.fs.normalize(session.root or (vim.uv.cwd() or ""))
  local files = require "agent.chat.files"
  local chat_text = require "agent.chat.text"
  local per_file = cfg.max_mention_chars or 12000
  local budget = cfg.max_context_chars or 12000
  local sections, seen = {}, {}
  for _, path in ipairs(paths) do
    if #sections >= M.MAX_FILES or budget <= 0 then
      break
    end
    local full = resolve(root, path)
    if full and not seen[full] and vim.fn.getfsize(full) <= 2 * 1024 * 1024 then
      local body = files.read(full)
      if body and body ~= "" then
        seen[full] = true
        local clipped = chat_text.clip(body, math.min(per_file, budget))
        sections[#sections + 1] = {
          name = "file:" .. vim.fn.fnamemodify(full, ":~:."),
          text = clipped,
        }
        budget = budget - #clipped
      end
    end
  end
  return sections
end

--- Marks the last assistant answer's `@need:` request as used (once it is
--- really being sent).
---@param session table?
function M.mark(session)
  local messages = (session and session.messages) or {}
  for i = #messages, 1, -1 do
    if messages[i].role == "assistant" then
      messages[i].meta = messages[i].meta or {}
      messages[i].meta.needs_used = true
      return
    end
  end
end

--- Instruction added to every chat profile's system prompt (one place).
M.RULE = [[
If a file you need is not in the context, add a line `@need: path/one, path/two` (project-relative).
Leader injects those files in the next turn; never guess their contents.]]

return M
