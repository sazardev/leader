-- Chat prompt: system + history + sections + the new user turn.
-- Stable from the start (system, then history), volatile last (new turn), so
-- prefix-caching servers (Ollama, llama.cpp, vLLM) reuse the head.
--
-- The profile (ask/write/minimal) owns the role and the closing instruction;
-- everything else is the same pipeline. `profiles.get` is pure, so tests can
-- assert every profile without a backend.
local settings = require("core.settings").agent
local profiles = require "agent.chat.profiles"

local M = {}

---@param session table
---@param clean string user text without mentions
---@param sections { name: string, text: string }[] injected (mentions + auto context)
---@param profile table? chat profile (defaults to the session's)
---@return string system, string prompt, string[] injected_names
function M.build(session, clean, sections, profile)
  profile = profile or profiles.of(session, settings.chat.profile)
  local budget = profile.max_history_chars or settings.chat.max_history_chars or 60000
  local history = require("agent.chat.session").history(session, budget)
  local parts = {}
  for _, m in ipairs(history) do
    local tag = m.role == "user" and "user" or "assistant"
    parts[#parts + 1] = ("<%s>\n%s\n</%s>"):format(tag, m.text or "", tag)
  end
  for _, s in ipairs(sections or {}) do
    parts[#parts + 1] = ("<%s>\n%s\n</%s>"):format(s.name, s.text, s.name)
  end
  parts[#parts + 1] = ("<user>\n%s\n</user>"):format(clean)
  parts[#parts + 1] = "<task>\n" .. (profile.task:gsub("%%s", settings.language or "English")) .. "\n</task>"
  local system = profile.system
    .. "\n\nProject: "
    .. (session.root or (vim.uv.cwd() or ""))
    .. "\nProfile: "
    .. profile.label
    .. "\nLanguage: "
    .. (settings.language or "English")
  return system, table.concat(parts, "\n"), vim.tbl_map(function(s)
    return s.name
  end, sections or {})
end

return M
