-- ── Reading the results (pure) ───────────────────────────────────────────────
-- One result per (case, model, sample). Here they are grouped per action × model and turned into the numbers that get
-- published: pass@1 (the share of ALL samples that passed: what you get on a single try), pass@k (the share of CASES with
-- at least one passing sample: what best-of-k with a checker could reach), how often the output was usable at all, and
-- what it cost.
--
--   result = { case, action, model, sample, status = "ok"|"error"|"skipped", parsed, applied, answers = { name = bool },
--              pass, tokens_in, tokens_out, cost, ms }
local M = {}

---@class AgentEvalGroup
---@field action string
---@field model string
---@field n integer         samples that ran (an infrastructure error is not a sample: see `errors`)
---@field errors integer    calls that never produced an answer (server error, timeout): they say nothing about the model
---@field cases integer
---@field pass1 number      0..1
---@field passk number      0..1
---@field flaky integer     cases whose samples disagree (some pass, some fail): the predictability of the model
---@field parsed number     0..1  the output could be read
---@field applied number    0..1  and it changed the code (or produced findings)
---@field tokens_in number  average per sample
---@field tokens_out number
---@field cost number       total dollars
---@field per_pass number?  dollars per passing sample: what a USABLE answer costs (nil when nothing passed or it is free)
---@field ms number         average
---@field attempts number   average calls per sample (repairs and escalations included)
---@field escalated number  0..1  went to the main model

---@param results table[]
---@return AgentEvalGroup[] groups sorted by action, then model
function M.aggregate(results)
  local by, order = {}, {}
  for _, r in ipairs(results) do
    if r.status ~= "skipped" then
      local key = r.action .. "\0" .. r.model
      local g = by[key]
      if not g then
        g = {
          action = r.action,
          model = r.model,
          n = 0,
          errors = 0,
          passed = 0,
          parsed = 0,
          applied = 0,
          tin = 0,
          tout = 0,
          cost = 0,
          ms = 0,
          tries = 0,
          escalated = 0,
          outcomes = {},
        }
        by[key] = g
        order[#order + 1] = key
      end
      g.cost = g.cost + (r.cost or 0)
      if r.status == "error" then
        g.errors = g.errors + 1
      else
        g.n = g.n + 1
        g.passed = g.passed + (r.pass and 1 or 0)
        g.parsed = g.parsed + (r.parsed and 1 or 0)
        g.applied = g.applied + (r.applied and 1 or 0)
        g.tin = g.tin + (r.tokens_in or 0)
        g.tout = g.tout + (r.tokens_out or 0)
        g.ms = g.ms + (r.ms or 0)
        g.tries = g.tries + (r.attempts or 1)
        g.escalated = g.escalated + (r.escalated and 1 or 0)
        local o = g.outcomes[r.case] or { pass = 0, fail = 0 }
        g.outcomes[r.case] = o
        o[r.pass and "pass" or "fail"] = o[r.pass and "pass" or "fail"] + 1
      end
    end
  end
  local groups = {}
  for _, key in ipairs(order) do
    local g = by[key]
    local cases, any, flaky = 0, 0, 0
    for _, o in pairs(g.outcomes) do
      cases = cases + 1
      any = any + (o.pass > 0 and 1 or 0)
      flaky = flaky + ((o.pass > 0 and o.fail > 0) and 1 or 0)
    end
    local n = math.max(g.n, 1)
    groups[#groups + 1] = {
      action = g.action,
      model = g.model,
      n = g.n,
      errors = g.errors,
      cases = cases,
      pass1 = g.passed / n,
      passk = cases > 0 and any / cases or 0,
      flaky = flaky,
      parsed = g.parsed / n,
      applied = g.applied / n,
      tokens_in = g.tin / n,
      tokens_out = g.tout / n,
      cost = g.cost,
      per_pass = (g.cost > 0 and g.passed > 0) and g.cost / g.passed or nil,
      ms = g.ms / n,
      attempts = g.tries / n,
      escalated = g.escalated / n,
    }
  end
  table.sort(groups, function(a, b)
    if a.action ~= b.action then
      return a.action < b.action
    end
    return a.model < b.model
  end)
  return groups
end

---@param x number 0..1
---@return string
local function pct(x)
  return ("%d%%"):format(math.floor(x * 100 + 0.5))
end

--- The table that goes into the docs and the terminal. Columns that would be noise stay out: `errors` only when something
--- errored, `flaky` only when samples were repeated
---@param groups AgentEvalGroup[]
---@return string[] lines
function M.markdown(groups)
  local any_errors, repeated = false, false
  for _, g in ipairs(groups) do
    any_errors = any_errors or g.errors > 0
    repeated = repeated or g.n > g.cases
  end
  local head = { "action", "model", "cases", "samples", "pass@1", "pass@k" }
  if repeated then
    head[#head + 1] = "flaky"
  end
  vim.list_extend(head, { "usable", "tries", "tokens in→out", "cost", "per pass", "time" })
  if any_errors then
    head[#head + 1] = "errors"
  end
  local lines = {
    "| " .. table.concat(head, " | ") .. " |",
    "|" .. string.rep(" --- |", 2) .. string.rep(" ---: |", #head - 2),
  }
  for _, g in ipairs(groups) do
    local row = { g.action, g.model, tostring(g.cases), tostring(g.n) }
    if g.n == 0 then
      vim.list_extend(row, { "—", "—" })
    else
      vim.list_extend(row, { pct(g.pass1), pct(g.passk) })
    end
    if repeated then
      row[#row + 1] = tostring(g.flaky)
    end
    vim.list_extend(row, {
      g.n == 0 and "—" or pct(g.parsed),
      ("%.1f"):format(g.attempts),
      ("%d→%d"):format(g.tokens_in, g.tokens_out),
      g.cost > 0 and ("$%.4f"):format(g.cost) or "free",
      g.per_pass and ("$%.4f"):format(g.per_pass) or "—",
      ("%.1fs"):format(g.ms / 1000),
    })
    if any_errors then
      row[#row + 1] = tostring(g.errors)
    end
    lines[#lines + 1] = "| " .. table.concat(row, " | ") .. " |"
  end
  return lines
end

--- An error message as one short line (a server's error body is several)
---@param err string?
---@return string
function M.short(err)
  local line = vim.split(err or "?", "\n", { plain = true })[1]
  return #line > 100 and (line:sub(1, 97) .. "…") or line
end

--- What failed, one line per failed result: "fix/py-x · model · outside, contains"
---@param results table[]
---@return string[]
function M.failures(results)
  local out = {}
  for _, r in ipairs(results) do
    if r.status ~= "skipped" and not r.pass then
      local why = r.status == "error" and ("error: " .. M.short(r.error))
        or (not r.parsed and "unusable output")
        or table.concat(r.failed or {}, ", ")
      out[#out + 1] = ("%s · %s · %s"):format(r.case, r.model, why)
    end
  end
  return out
end

--- Compares two aggregates: what got worse by more than `tolerance` (a share, 0.1 = ten points) per action × model
---@param baseline AgentEvalGroup[]
---@param current AgentEvalGroup[]
---@param tolerance number?
---@return { action: string, model: string, was: number, now: number }[] regressions
function M.regressions(baseline, current, tolerance)
  tolerance = tolerance or 0.1
  local was = {}
  for _, g in ipairs(baseline) do
    if (g.n or 1) > 0 then
      was[g.action .. "\0" .. g.model] = g.pass1
    end
  end
  local out = {}
  for _, g in ipairs(current) do
    local before = was[g.action .. "\0" .. g.model]
    if before and (g.n or 1) > 0 and before - g.pass1 > tolerance + 1e-9 then
      out[#out + 1] = { action = g.action, model = g.model, was = before, now = g.pass1 }
    end
  end
  return out
end

return M
