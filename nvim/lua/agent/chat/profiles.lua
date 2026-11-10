-- ── Chat profiles (pure) ────────────────────────────────────────────────────
-- Zed-style modes for the chat: the profile decides what the model is told,
-- how much automatic context it receives and how much chrome the answer shows.
--
--   ask      read-only: explain and locate; never proposes edits
--   write    the full coding partner: plans and code changes are welcome
--   minimal  few tokens and few lines: no auto context, no thinking footer
--
-- A session stores its profile (`profile`), so history opens with the same
-- behavior it had. The prompt builder and context collector read it; no UI here.
local M = {}

M.ORDER = { "ask", "write", "minimal" }

---@class ChatProfile
---@field id string
---@field label string
---@field icon string
---@field description string
---@field hint string
---@field context table<string, boolean>
---@field max_context_chars integer?   cap for auto-injected context (0/nil = none)
---@field max_history_chars integer?   cap for the conversation sent to the model
---@field show_thinking boolean        render the reasoning stream
---@field show_meta boolean            render token/cost footers
---@field system string               role of the model
---@field task string                 closing instruction for every turn

M.PROFILES = {
  ask = {
    id = "ask",
    label = "Ask",
    icon = "?",
    description = "Read-only answers about the code",
    hint = "explains, never edits",
    context = { rules = true, buffer = true, diagnostics = true, git = true, skills = true, mcp = false },
    max_context_chars = 8000,
    show_thinking = true,
    show_meta = true,
    system = [[
You are Leader Chat in Ask mode, a precise read-only code companion inside the Leader editor (Neovim).
You answer questions about the project, explain code and point at the exact places that matter.

Ask-mode contract (never break it):
- Do not edit files and do not offer a project diff. If the user asks how to change something, answer
  with the smallest explanation or guidance, not a full patch unless they explicitly request one.
- Ground every claim in the injected code or history. Name the file, symbol or line you mean.
- Say exactly what information is missing instead of inventing an API, a field or a file.
- Prefer a short direct answer first, then the detail that supports it. Markdown; code fenced with
  its language when a snippet is genuinely useful.
]],
    task = "Answer the user's last turn. Read-only: explain, locate and reason; do not propose edits. In %s. Markdown; code in fenced blocks. If you need more context, name the file or section you need.",
  },
  write = {
    id = "write",
    label = "Write",
    icon = "✎",
    description = "The full coding partner",
    hint = "plans, code and changes",
    context = { rules = true, buffer = true, diagnostics = true, git = true, skills = true, mcp = true },
    max_context_chars = 12000,
    show_thinking = true,
    show_meta = true,
    system = [[
You are Leader Chat in Write mode, a full agentic coding partner inside the Leader editor (Neovim).
You are backend-agnostic: Leader orchestrates you, you do not know which CLI runs you.
One turn per request, no tools of your own: you propose, Leader executes and shows you back.

Transparency contract (never break it):
- Say what you will do before doing it (plan, steps).
- When you need a file you do not have, name it and Leader will inject it next turn.
- Code answers are fenced blocks with the path in the language field when they are a full file,
  e.g. ```lua: nvim/lua/foo.lua
- Never invent APIs, fields or files. If information is missing, say exactly what is missing.
- Show your reasoning briefly when it matters, then the answer. No filler, no repetition.
]],
    task = "Answer the user's last turn. In %s. Markdown; code in fenced blocks. If you propose edits, list them as steps first. If you need more context, name the sections (file:…, diagnostics, rules) you need — Leader will add them next turn.",
  },
  minimal = {
    id = "minimal",
    label = "Minimal",
    icon = "·",
    description = "Short answers, almost no context",
    hint = "fast and terse",
    context = { rules = false, buffer = false, diagnostics = false, git = false, skills = false, mcp = false },
    max_context_chars = 0,
    max_history_chars = 12000,
    show_thinking = false,
    show_meta = false,
    system = [[
You are Leader Chat in Minimal mode. Answer directly and briefly. No preamble, no recap, no plan.
Use the user's language. Markdown only when it helps; code fenced when it is the answer.
]],
    task = "Answer in %s with the fewest useful words. No preamble. Code only when it is the answer.",
  },
}

---@param id string?
---@return ChatProfile
function M.get(id)
  return M.PROFILES[id or ""] or M.PROFILES.write
end

---@return ChatProfile[]
function M.list()
  return vim.tbl_map(function(id)
    return M.PROFILES[id]
  end, M.ORDER)
end

--- The next profile in the cycle (used by shortcuts).
---@param id string?
---@param delta integer?
---@return string
function M.cycle(id, delta)
  delta = delta or 1
  local at = 1
  for i, name in ipairs(M.ORDER) do
    if name == id then
      at = i
      break
    end
  end
  return M.ORDER[((at - 1 + delta) % #M.ORDER) + 1]
end

--- Label of a profile id ("write" → "Write"), safe for a nil id.
---@param id string?
---@return string
function M.label(id)
  return M.get(id).label
end

--- Resolve the profile of a session, falling back to the configured default.
---@param session table?
---@param fallback string?
---@return ChatProfile
function M.of(session, fallback)
  return M.get((session and session.profile) or fallback or "write")
end

return M
