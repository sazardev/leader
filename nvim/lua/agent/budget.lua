-- ── Spend budget ─────────────────────────────────────────────────────────────
-- Decides, BEFORE a request is made, whether it should go ahead, ask first, or not happen. Pure: the history, the limits
-- and the clock come in as arguments (the adapter that reads them is agent/guards/budget.lua), so it is tested alone.
--
-- The estimate is deliberately simple: tokens ≈ characters / 3.5 (what code and English prose come to), and the cost of
-- a request is what YOUR history says tokens cost with that model (dollars per input token, outputs included), so it
-- needs no price table and follows whatever backend or model you use.
local M = {}

local CHARS_PER_TOKEN = 3.5
local SAMPLE = 30 -- recent runs of a model that set its price per token

---@param chars integer
---@return integer
function M.tokens(chars)
  return math.ceil(chars / CHARS_PER_TOKEN)
end

--- 498 → "498", 1800 → "1.8k", 24000 → "24k"
---@param n integer
---@return string
local function short(n)
  if n < 1000 then
    return tostring(n)
  end
  return (("%.1fk"):format(n / 1000):gsub("%.0k$", "k"))
end

---@class AgentBudgetRequest
---@field action string
---@field backend string?
---@field model string?
---@field chars integer      what is about to be sent (system + message)
---@field count integer?     how many requests this stands for (a batch); default 1

---@class AgentBudgetLimits
---@field confirm_tokens integer?
---@field confirm_usd number?
---@field day_usd number?
---@field session_usd number?
---@field warn_ratio number?

---@class AgentBudgetVerdict
---@field level "ok"|"confirm"|"block"
---@field tokens integer
---@field cost number?       estimated dollars (nil when the history has no price for this model yet)
---@field reasons string[]   why it asks or blocks, one line each
---@field spent { day: number, session: number }

--- Dollars per input token for `backend/model`: what the recent runs of that model cost, over what they sent
---@param runs table[]
---@param backend string?
---@param model string?
---@return number?
function M.price_per_token(runs, backend, model)
  local cost, tokens, seen = 0, 0, 0
  for i = #runs, 1, -1 do
    local r = runs[i]
    local u = r.usage or {}
    if
      r.t ~= "event"
      and r.backend == backend
      and r.model == model
      and (u.cost or 0) > 0
      and (u.tokens_in or 0) > 0
    then
      cost = cost + u.cost
      tokens = tokens + u.tokens_in
      seen = seen + 1
      if seen >= SAMPLE then
        break
      end
    end
  end
  return tokens > 0 and cost / tokens or nil
end

--- What the runs from `since` on cost, in dollars
---@param runs table[]
---@param since integer os.time()
---@return number
function M.spent_since(runs, since)
  local sum = 0
  for _, r in ipairs(runs) do
    if r.t ~= "event" and (r.ts or 0) >= since then
      sum = sum + ((r.usage or {}).cost or 0)
    end
  end
  return sum
end

---@param now integer os.time()
---@return integer
function M.day_start(now)
  local d = os.date("*t", now)
  return os.time { year = d.year, month = d.month, day = d.day, hour = 0 }
end

---@param req AgentBudgetRequest
---@param limits AgentBudgetLimits
---@param ctx { runs: table[], now: integer, session_start: integer }
---@return AgentBudgetVerdict
function M.check(req, limits, ctx)
  local count = req.count or 1
  local tokens = M.tokens(req.chars) * count
  local price = M.price_per_token(ctx.runs, req.backend, req.model)
  local cost = price and tokens * price or nil
  local spent = {
    day = M.spent_since(ctx.runs, M.day_start(ctx.now)),
    session = M.spent_since(ctx.runs, ctx.session_start),
  }
  local verdict = { level = "ok", tokens = tokens, cost = cost, reasons = {}, spent = spent }

  local function raise(level, reason)
    if level == "block" or verdict.level == "ok" then
      verdict.level = level
    end
    verdict.reasons[#verdict.reasons + 1] = reason
  end

  local warn = limits.warn_ratio or 0.8
  for _, cap in ipairs {
    { limit = limits.day_usd, used = spent.day, name = "today" },
    { limit = limits.session_usd, used = spent.session, name = "this session" },
  } do
    if cap.limit then
      if cap.used >= cap.limit or (cost and cap.used + cost >= cap.limit) then
        raise("block", ("%s's budget is used up: $%.4f of $%.2f spent"):format(cap.name, cap.used, cap.limit))
      elseif cap.used + (cost or 0) >= cap.limit * warn then
        raise("confirm", ("%s: $%.4f of $%.2f spent"):format(cap.name, cap.used, cap.limit))
      end
    end
  end
  if limits.confirm_tokens and tokens > limits.confirm_tokens then
    raise("confirm", ("~%s tokens (it asks above %s)"):format(short(tokens), short(limits.confirm_tokens)))
  end
  if limits.confirm_usd and cost and cost > limits.confirm_usd then
    raise("confirm", ("~$%.3f (it asks above $%.2f)"):format(cost, limits.confirm_usd))
  end
  return verdict
end

--- "~1.8k tokens · ~$0.0007"
---@param verdict { tokens: integer, cost: number? }
---@return string
function M.describe(verdict)
  local text = ("~%s tokens"):format(short(verdict.tokens))
  if verdict.cost then
    text = text .. (" · ~$%.4f"):format(verdict.cost)
  end
  return text
end

return M
