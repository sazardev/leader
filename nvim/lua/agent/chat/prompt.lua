-- Chat prompt: system + history + sections + the new user turn.
-- Stable from the start (system, then history), volatile last (new turn), so
-- prefix-caching servers (Ollama, llama.cpp, vLLM) reuse the head.
local settings = require("core.settings").agent

local M = {}

local ROLE = [[
You are Leader Chat, a full agentic coding partner inside the Leader editor (Neovim).
You are backend-agnostic: Leader orchestrates you, you do not know which CLI runs you.
One turn per request, no tools of your own: you propose, Leader executes and shows you back.

Transparency contract (never break it):
- Say what you will do before doing it (plan, steps).
- When you need a file you do not have, name it and Leader will inject it next turn.
- Code answers are fenced blocks with the path in the language field when they are a full file,
  e.g. ```lua: nvim/lua/foo.lua
- Never invent APIs, fields or files. If information is missing, say exactly what is missing.
- Show your reasoning briefly when it matters, then the answer. No filler, no repetition.
]]

---@param session table
---@param clean string user text without mentions
---@param sections { name: string, text: string }[] injected (mentions + auto context)
---@return string system, string prompt, string[] injected_names
function M.build(session, clean, sections)
  local history = require("agent.chat.session").history(session, settings.chat.max_history_chars or 60000)
  local parts = {}
  for _, m in ipairs(history) do
    local tag = m.role == "user" and "user" or "assistant"
    parts[#parts + 1] = ("<%s>\n%s\n</%s>"):format(tag, m.text or "", tag)
  end
  for _, s in ipairs(sections) do
    parts[#parts + 1] = ("<%s>\n%s\n</%s>"):format(s.name, s.text, s.name)
  end
  parts[#parts + 1] = ("<user>\n%s\n</user>"):format(clean)
  parts[#parts + 1] = "<task>\nAnswer the user's last turn. In "
    .. (settings.language or "English")
    .. ". Markdown; code in fenced blocks. If you propose edits, list them as steps first. If you need more context, name the sections (file:…, diagnostics, rules) you need — Leader will add them next turn.\n</task>"
  local system = ROLE
    .. "\n\nProject: "
    .. (session.root or (vim.uv.cwd() or ""))
    .. "\nLanguage: "
    .. (settings.language or "English")
  return system, table.concat(parts, "\n"), vim.tbl_map(function(s)
    return s.name
  end, sections)
end

return M
