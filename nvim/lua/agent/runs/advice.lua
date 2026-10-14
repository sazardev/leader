-- ── What the history suggests ────────────────────────────────────────────────
-- Reads the runs and says, in plain sentences, where the money did not turn into applied code. Pure (the report passes the
-- runs and the settings it wants considered). Every sentence needs a sample big enough to mean something.
local fmt = require "agent.runs.format"

local M = {}

local MIN_RUNS = 5 -- proposals of an action+model before its acceptance rate is worth a comment
local LOW_RATE = 0.35 -- below this share accepted, the action is not paying for itself
local WASTE_SHARE = 0.4 -- share of the spend that went to proposals nobody applied

---@param runs table[]
---@return table[] rows { action, model, done, accepted, cost }
function M.acceptance(runs)
  local by, order = {}, {}
  for _, r in ipairs(runs) do
    if r.t ~= "event" and r.output == "replace" and r.status == "done" then
      local key = r.action .. "\0" .. fmt.model(r)
      if not by[key] then
        by[key] = { action = r.action, model = fmt.model(r), tier = r.tier, done = 0, accepted = 0, cost = 0 }
        order[#order + 1] = key
      end
      local row = by[key]
      row.done = row.done + 1
      row.cost = row.cost + ((r.usage or {}).cost or 0)
      if r.outcome == "accepted" then
        row.accepted = row.accepted + 1
      end
    end
  end
  return vim.tbl_map(function(k)
    return by[k]
  end, order)
end

---@param runs table[]
---@param ctx { budget: table?, now: integer? }?
---@return string[] markdown lines, empty when there is nothing to say
function M.build(runs, ctx)
  ctx = ctx or {}
  local out = {}

  for _, row in ipairs(M.acceptance(runs)) do
    if row.done >= MIN_RUNS and row.accepted / row.done < LOW_RATE then
      out[#out + 1] = ("- `%s` on %s: %d of %d proposals accepted (%d%%), %s spent. %s"):format(
        row.action,
        row.model,
        row.accepted,
        row.done,
        math.floor(row.accepted / row.done * 100),
        fmt.money(row.cost),
        row.tier == "light"
            and "Give it a more specific instruction, or run it with `refine` (Tab) instead of starting over."
          or "A more specific instruction usually helps; if it keeps missing, `settings.agent.tiers = { "
            .. row.action
            .. ' = "light" }` makes it cheaper to be wrong.'
      )
    end
  end

  -- how much of everything went to proposals that were never applied
  local total, wasted = 0, 0
  for _, r in ipairs(runs) do
    if r.t ~= "event" then
      local c = (r.usage or {}).cost or 0
      total = total + c
      if r.output == "replace" and r.status == "done" and r.outcome ~= "accepted" then
        wasted = wasted + c
      end
    end
  end
  if total > 0 and wasted / total >= WASTE_SHARE then
    out[#out + 1] = ("- %d%% of what you spent (%s) went to proposals that were not applied: `refine` (Tab) corrects one in place for about the price of a single run."):format(
      math.floor(wasted / total * 100),
      fmt.money(wasted)
    )
  end

  -- regressions: how often the verifier had to ask for another attempt, and whether it worked
  local retries, retries_ok = 0, 0
  for _, r in ipairs(runs) do
    if r.t ~= "event" and r.action == "verify_fix" then
      retries = retries + 1
      if r.outcome == "accepted" then
        retries_ok = retries_ok + 1
      end
    end
  end
  if retries > 0 then
    out[#out + 1] = ("- The verifier asked for %d retr%s after accepted code broke something; %d ended accepted."):format(
      retries,
      retries == 1 and "y" or "ies",
      retries_ok
    )
  end
  return out
end

--- The budget line of the report: what today cost against the cap, if there is one
---@param runs table[]
---@param budget table settings.agent.budget
---@param now integer
---@return string[]
function M.budget_lines(runs, budget, now)
  if not budget or not budget.enabled or not (budget.day_usd or budget.session_usd) then
    return {}
  end
  local spend = require "agent.budget"
  local lines = {}
  if budget.day_usd then
    local today = spend.spent_since(runs, spend.day_start(now))
    lines[#lines + 1] = ("- **Today:** %s of %s (%d%%)"):format(
      fmt.money(today),
      fmt.money(budget.day_usd),
      math.floor(today / budget.day_usd * 100)
    )
  end
  if budget.session_usd then
    lines[#lines + 1] = ("- **Session cap:** %s (it blocks requests once the session reaches it)"):format(
      fmt.money(budget.session_usd)
    )
  end
  return lines
end

return M
