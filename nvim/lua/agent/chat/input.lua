-- ── Input behavior (pure) ───────────────────────────────────────────────────
-- History navigation and the height the input needs for its text. No windows:
-- the caller reads the buffer, passes the lines and applies the result.
local chat_text = require "agent.chat.text"

local M = {}

--- Texts of the previous user messages, oldest first.
---@param session table?
---@return string[]
function M.history(session)
  local out = {}
  for _, m in ipairs((session and session.messages) or {}) do
    if m.role == "user" and (m.text or "") ~= "" then
      out[#out + 1] = m.text
    end
  end
  return out
end

--- Next history position. `state` = { idx = 0, draft = "" } (0 = the draft).
--- dir -1 = older, 1 = newer. Returns the text to put in the input and the new
--- state (pure; the caller stores it).
---@param state { idx: integer, draft: string }
---@param list string[]
---@param dir integer
---@param current string the draft text right now
---@return string text, { idx: integer, draft: string }
function M.step(state, list, dir, current)
  if #list == 0 then
    return current, state
  end
  if dir < 0 then
    if state.idx == 0 then
      state = { idx = 0, draft = current }
    end
    state = { idx = math.min(state.idx + 1, #list), draft = state.draft }
  else
    state = { idx = math.max((state.idx or 0) - 1, 0), draft = state.draft }
  end
  local text = state.idx == 0 and (state.draft or "") or list[#list - state.idx + 1]
  return text, state
end

--- Height the input needs: wrapped display rows, clamped to [1, max].
---@param lines string[]
---@param width integer
---@param max integer
---@return integer
function M.height(lines, width, max)
  return math.max(1, math.min(max, chat_text.height(lines, width)))
end

return M
