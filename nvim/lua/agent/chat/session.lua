-- Chat session: the in-memory model of one persistent chat.
-- A session = { id, title, root, backend, model, effort, messages, totals, ... }.
-- Messages are { role = "user"|"assistant"|"thinking"|"tool", text, ts, usage?, meta? }.
-- Pure state (no UI, no processes). Persistence lives in chat/store.lua.
local M = {}

---@class ChatMessage
---@field role string
---@field text string
---@field ts integer
---@field usage table?
---@field meta table?

---@class ChatSession
---@field id string
---@field title string
---@field root string
---@field profile string?
---@field backend string?
---@field model string?
---@field effort string?
---@field messages ChatMessage[]
---@field tokens_in integer
---@field tokens_out integer
---@field cost number
---@field turns integer
---@field created integer
---@field updated integer

local seq = 0
local function sid()
  seq = seq + 1
  return ("chat-%d-%d"):format(os.time(), seq)
end

---@return ChatSession
function M.new(opts)
  opts = opts or {}
  local now = os.time()
  return {
    id = opts.id or sid(),
    title = opts.title or "New chat",
    root = opts.root or (vim.uv.cwd() or ""),
    profile = opts.profile,
    backend = opts.backend,
    model = opts.model,
    effort = opts.effort,
    -- messages intentionally not serialized: the store keeps the transcript too
    messages = opts.messages or {},
    tokens_in = opts.tokens_in or 0,
    tokens_out = opts.tokens_out or 0,
    cost = opts.cost or 0,
    turns = opts.turns or 0,
    created = opts.created or now,
    updated = opts.updated or now,
  }
end

---@param s ChatSession
---@param msg ChatMessage
function M.add(s, msg)
  msg.ts = msg.ts or os.time()
  s.messages[#s.messages + 1] = msg
  s.updated = os.time()
  if s.title == "New chat" and msg.role == "user" then
    -- the first line that says something: list/heading markers and backticks out, one line only
    for line in (msg.text or ""):gmatch "[^\n]+" do
      line =
        line:gsub("\27%[[%d;?]*[ -/]*[@-~]", ""):gsub("^%s*#*%s*", ""):gsub("^%s*[-*+]%s+", ""):gsub("^%s*>%s*", "")
      line = line:gsub("`", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
      if line ~= "" then
        s.title = #line > 60 and (line:sub(1, 60) .. "…") or line
        break
      end
    end
    if s.title == "New chat" then
      s.title = "Chat"
    end
  end
end

---@param s ChatSession
---@param usage table? { tokens_in?, tokens_out?, cost?, ms? }
function M.charge(s, usage)
  if not usage then
    return
  end
  s.tokens_in = s.tokens_in + (usage.tokens_in or 0)
  s.tokens_out = s.tokens_out + (usage.tokens_out or 0)
  s.cost = s.cost + (usage.cost or 0)
end

--- History sent to the model: last turns within max_chars, oldest first.
---@param s ChatSession
---@param max_chars integer
---@return ChatMessage[] messages, integer dropped_chars  characters left out (oldest turns)
function M.history(s, max_chars)
  local out, budget, dropped = {}, max_chars or 60000, 0
  for i = #s.messages, 1, -1 do
    local m = s.messages[i]
    if m.role == "user" or m.role == "assistant" then
      local len = #(m.text or "")
      if budget - len < 0 and #out > 0 then
        -- everything older is left out: count it so the footer can say so
        for j = i, 1, -1 do
          local old = s.messages[j]
          if old.role == "user" or old.role == "assistant" then
            dropped = dropped + #(old.text or "")
          end
        end
        break
      end
      table.insert(out, 1, m)
      budget = budget - len
    end
  end
  return out, dropped
end

return M
