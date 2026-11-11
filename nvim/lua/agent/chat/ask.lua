-- ── Ask blocks: a question with options (pure) ──────────────────────────────
-- The model may end an answer with a fenced ```ask block:
--
--   ```ask
--   Which database should the project use?
--   - PostgreSQL
--   - SQLite
--   ```
--
-- `parse` reads the LAST block (question + options); `of` reads the last
-- assistant message of a session. No UI here: chat/init opens the selector and
-- chat/window fills the composer, so the user can still write their own answer.
local M = {}

---@class ChatAsk
---@field question string
---@field options string[]

---@param line string
---@param info string
---@return boolean
local function opens(line, info)
  local _, got = line:match "^(%s*```%s*)(.-)%s*$"
  return got == info
end

---@param text string
---@return ChatAsk?
function M.parse(text)
  local lines = vim.split(text or "", "\n", { plain = true })
  local found
  local i = 1
  while i <= #lines do
    if opens(lines[i], "ask") then
      local body, j = {}, i + 1
      while j <= #lines and not lines[j]:match "^%s*```%s*$" do
        body[#body + 1] = lines[j]
        j = j + 1
      end
      if j <= #lines then -- a block that never closes is not a question
        local question, options = {}, {}
        for _, line in ipairs(body) do
          local option = line:match "^%s*[%-%*%+]%s+(.+)$" or line:match "^%s*%d+[%)%.]%s+(.+)$"
          if option then
            option = option:gsub("%s+$", "")
          end
          if option and option ~= "" then
            options[#options + 1] = option
          elseif line:find "%S" then
            question[#question + 1] = (line:gsub("^%s+", ""):gsub("%s+$", ""))
          end
        end
        if #options > 0 then
          found = {
            question = #question > 0 and table.concat(question, " ") or "Choose one",
            options = options,
          }
        end
      end
      i = j
    end
    i = i + 1
  end
  return found
end

--- Last assistant message of `session` as an ask, or nil (also nil when that
--- answer does not carry a block).
---@param session table?
---@return ChatAsk?
function M.of(session)
  local messages = (session and session.messages) or {}
  for i = #messages, 1, -1 do
    if messages[i].role == "assistant" then
      return M.parse(messages[i].text)
    end
  end
end

--- Instruction added to every chat profile's system prompt (one place, short:
--- it rides along on every turn).
M.RULE = [[
When you genuinely need the user to decide something, end with a fenced `ask` block: the
question on its own line, then one `- option` per line (2-4 short options). Leader shows a
selector and the user can still write their own answer. Never use it for rhetorical questions.]]

return M
