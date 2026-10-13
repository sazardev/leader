-- ── Spend metrics (markdown) ─────────────────────────────────────────────────
-- Aggregates the history runs to answer: how much do I spend?, on which actions and models?,
-- how much of it ended up in changes I actually applied?, where does the prompt go? Pure: takes the list.
local fmt = require "agent.runs.format"

local M = {}

local DAY = 86400

---@param runs table[]
---@return table
local function sum(runs)
  local t = { runs = #runs, cost = 0, tin = 0, tout = 0, ms = 0, cache_read = 0 }
  for _, r in ipairs(runs) do
    local u = r.usage or {}
    t.cost = t.cost + (u.cost or 0)
    t.tin = t.tin + (u.tokens_in or 0)
    t.tout = t.tout + (u.tokens_out or 0)
    t.cache_read = t.cache_read + (u.cache_read or 0)
    t.ms = t.ms + (r.ms or 0)
  end
  return t
end

---@param runs table[]
---@param key fun(run: table): string
---@return table[] groups sorted by spend
local function group(runs, key)
  local by, order = {}, {}
  for _, r in ipairs(runs) do
    local k = key(r)
    if not by[k] then
      by[k] = {}
      order[#order + 1] = k
    end
    table.insert(by[k], r)
  end
  local list = {}
  for _, k in ipairs(order) do
    local t = sum(by[k])
    t.key, t.items = k, by[k]
    list[#list + 1] = t
  end
  table.sort(list, function(a, b)
    return a.cost > b.cost
  end)
  return list
end

---@param runs table[]
---@param pred fun(run: table): boolean
---@return table[]
local function where(runs, pred)
  return vim.tbl_filter(pred, runs)
end

---@param t table
---@return string
local function avg(t)
  return t.runs > 0 and fmt.money(t.cost / t.runs) or "—"
end

---@param t table
---@return string
local function avg_time(t)
  return t.runs > 0 and fmt.seconds(t.ms / t.runs) or "—"
end

--- Totals summary for the picker title
---@param runs table[]
---@return string
function M.headline(runs)
  local t = sum(runs)
  return ("%d runs · %s"):format(t.runs, fmt.money(t.cost))
end

---@param runs table[]
---@param now integer?
---@return string[]
function M.build(runs, now)
  now = now or os.time()
  local lines = { "# Agent usage", "" }
  if #runs == 0 then
    return vim.list_extend(lines, { "_No runs recorded yet._" })
  end

  -- ── periods ──
  local today = os.date("%Y-%m-%d", now)
  vim.list_extend(
    lines,
    { "| Period | Runs | Spend | Avg / run | Tokens in→out | Avg time |", "|---|---|---|---|---|---|" }
  )
  for _, p in ipairs {
    { "Today", where(runs, function(r)
      return os.date("%Y-%m-%d", r.ts) == today
    end) },
    { "Last 7 days", where(runs, function(r)
      return r.ts >= now - 7 * DAY
    end) },
    { "All time", runs },
  } do
    local t = sum(p[2])
    lines[#lines + 1] = ("| %s | %d | **%s** | %s | %s→%s | %s |"):format(
      p[1],
      t.runs,
      fmt.money(t.cost),
      avg(t),
      fmt.tokens(t.tin),
      fmt.tokens(t.tout),
      avg_time(t)
    )
  end

  -- ── by action ──
  vim.list_extend(lines, {
    "",
    "## By action",
    "",
    "| Action | Runs | Spend | Avg | Avg tokens in→out | Avg time | Applied |",
    "|---|---|---|---|---|---|---|",
  })
  for _, g in
    ipairs(group(runs, function(r)
      return r.action
    end))
  do
    local replace = where(g.items, function(r)
      return r.output == "replace" and r.status == "done"
    end)
    local accepted = #where(replace, function(r)
      return r.outcome == "accepted"
    end)
    local applied = #replace > 0 and ("%d/%d"):format(accepted, #replace) or "n/a"
    lines[#lines + 1] = ("| %s | %d | %s | %s | %s→%s | %s | %s |"):format(
      g.key,
      g.runs,
      fmt.money(g.cost),
      avg(g),
      fmt.tokens(g.runs > 0 and math.floor(g.tin / g.runs) or 0),
      fmt.tokens(g.runs > 0 and math.floor(g.tout / g.runs) or 0),
      avg_time(g),
      applied
    )
  end

  -- ── by model ──
  vim.list_extend(
    lines,
    { "", "## By model", "", "| Model | Runs | Spend | Avg | Avg time |", "|---|---|---|---|---|" }
  )
  for _, g in ipairs(group(runs, fmt.model)) do
    lines[#lines + 1] = ("| %s | %d | %s | %s | %s |"):format(g.key, g.runs, fmt.money(g.cost), avg(g), avg_time(g))
  end

  -- ── by day ──
  vim.list_extend(lines, { "", "## Last 14 days", "", "| Day | Runs | Spend |", "|---|---|---|" })
  local days = group(
    where(runs, function(r)
      return r.ts >= now - 14 * DAY
    end),
    function(r)
      return os.date("%Y-%m-%d", r.ts)
    end
  )
  table.sort(days, function(a, b)
    return a.key > b.key
  end)
  for _, d in ipairs(days) do
    lines[#lines + 1] = ("| %s | %d | %s |"):format(d.key, d.runs, fmt.money(d.cost))
  end

  -- ── where the money goes ──
  local replace = where(runs, function(r)
    return r.output == "replace" and r.status == "done"
  end)
  local accepted = where(replace, function(r)
    return r.outcome == "accepted"
  end)
  local not_applied = where(replace, function(r)
    return r.outcome ~= "accepted"
  end)
  local failed = where(runs, function(r)
    return r.status ~= "done"
  end)
  local all = sum(runs)
  vim.list_extend(lines, { "", "## Where the money goes", "" })
  if #accepted > 0 then
    lines[#lines + 1] = ("- **Cost per applied change:** %s (%d of %d proposals accepted)"):format(
      fmt.money(sum(replace).cost / #accepted),
      #accepted,
      #replace
    )
  elseif #replace > 0 then
    lines[#lines + 1] = ("- **Proposals applied:** 0 of %d"):format(#replace)
  end
  if #not_applied > 0 then
    local w = sum(not_applied)
    lines[#lines + 1] = ("- **Spent on proposals not applied** (rejected, discarded, never decided): %s over %d runs"):format(
      fmt.money(w.cost),
      w.runs
    )
  end
  if #failed > 0 then
    lines[#lines + 1] = ("- **Errors and cancellations:** %d runs, %s"):format(#failed, fmt.money(sum(failed).cost))
  end
  lines[#lines + 1] = ("- **Prompt cache:** %s of input tokens were cache reads%s"):format(
    all.tin > 0 and ("%.0f%%"):format(all.cache_read / all.tin * 100) or "0%",
    all.cache_read == 0 and " (caching is off by default: one-shot prompts never hit it)" or ""
  )

  -- ── anatomy of the prompt ──
  local n, system, message, target, context, per = 0, 0, 0, 0, 0, {}
  for _, r in ipairs(runs) do
    if r.chars then
      n = n + 1
      system, message, target, context =
        system + (r.chars.system or 0),
        message + (r.chars.message or 0),
        target + (r.chars.target or 0),
        context + (r.chars.context or 0)
      for _, c in ipairs(r.context or {}) do
        per[c.name] = per[c.name] or { total = 0 }
        per[c.name].total = per[c.name].total + c.chars
      end
    end
  end
  if n > 0 then
    local names = vim.tbl_keys(per)
    table.sort(names)
    local parts = vim.tbl_map(function(name)
      return ("%s %d"):format(name, per[name].total / n)
    end, names)
    vim.list_extend(lines, {
      "",
      "## Where the prompt goes (average chars per run)",
      "",
      ("system **%d** · message **%d** = target %d + context %d%s"):format(
        system / n,
        message / n,
        target / n,
        context / n,
        #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or ""
      ),
      "",
      "_About 4 chars ≈ 1 token. The CLI adds ~560 fixed input tokens on top (Claude Code overhead)._",
    })
  end

  -- ── the most expensive ──
  local costly = vim.list_slice(vim.deepcopy(runs), 1, #runs)
  table.sort(costly, function(a, b)
    return ((a.usage or {}).cost or 0) > ((b.usage or {}).cost or 0)
  end)
  vim.list_extend(lines, {
    "",
    "## Most expensive runs",
    "",
    "| When | Action | Model | Cost | Tokens | Target | Result |",
    "|---|---|---|---|---|---|---|",
  })
  for i = 1, math.min(5, #costly) do
    local r = costly[i]
    local u = r.usage or {}
    lines[#lines + 1] = ("| %s | %s | %s | %s | %s→%s | `%s` | %s |"):format(
      os.date("%m-%d %H:%M", r.ts),
      r.action,
      fmt.model(r),
      fmt.money(u.cost),
      fmt.tokens(u.tokens_in),
      fmt.tokens(u.tokens_out),
      fmt.target(r),
      fmt.outcome(r)
    )
  end
  return lines
end

return M
