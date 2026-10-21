-- ── What the events say (pure) ───────────────────────────────────────────────
-- The report of `<leader>aSl`: from the events of one project, how Leader has been doing, so what to improve is read from use and
-- not guessed. Everything here is an aggregate of counts, durations and costs; the events hold nothing else.
local M = {}

---@param n number
---@return string
local function usd(n)
  return n >= 0.01 and ("$%.2f"):format(n) or ("$%.4f"):format(n)
end

---@param part number
---@param whole number
---@return string
local function pct(part, whole)
  return whole > 0 and ("%d%%"):format(math.floor(part / whole * 100 + 0.5)) or "—"
end

---@param map table<string, number>
---@return { key: string, n: number }[]
local function ranked(map)
  local out = {}
  for key, n in pairs(map) do
    out[#out + 1] = { key = key, n = n }
  end
  table.sort(out, function(a, b)
    if a.n ~= b.n then
      return a.n > b.n
    end
    return a.key < b.key
  end)
  return out
end

---@param events table[]
---@return table
function M.aggregate(events)
  local a = {
    builds = {},
    outcomes = {},
    cost = 0,
    seconds = 0,
    fix_builds = 0,
    fix_rounds = 0,
    failing = {},
    check_runs = {},
    req_total = 0,
    req_proven = 0,
    placeholders = 0,
    regressions = 0,
    by_ext = {},
    by_model = {},
    actions = {},
    decisions = {},
    span = { from = nil, to = nil },
  }
  for _, e in ipairs(events) do
    if e.ts then
      a.span.from = math.min(a.span.from or e.ts, e.ts)
      a.span.to = math.max(a.span.to or e.ts, e.ts)
    end
    if e.kind == "build.finish" then
      a.builds[#a.builds + 1] = e
      a.outcomes[e.outcome or "other"] = (a.outcomes[e.outcome or "other"] or 0) + 1
      a.cost = a.cost + (e.cost or 0)
      a.seconds = a.seconds + (e.seconds or 0)
      if (e.fix_rounds or 0) > 0 then
        a.fix_builds = a.fix_builds + 1
        a.fix_rounds = a.fix_rounds + e.fix_rounds
      end
      for _, c in ipairs(e.checks or {}) do
        a.check_runs[c.label] = (a.check_runs[c.label] or 0) + 1
        if c.ok == false then
          a.failing[c.label] = (a.failing[c.label] or 0) + 1
        end
      end
      a.req_total = a.req_total + (e.req_total or 0)
      a.req_proven = a.req_proven + (e.req_proven or 0)
      a.placeholders = a.placeholders + (e.placeholders or 0)
      a.regressions = a.regressions + (e.regressions or 0)
      for _, f in ipairs(e.per_file or {}) do
        local x = a.by_ext[f.ext or "?"] or { n = 0, failed = 0, tin = 0, tout = 0, cost = 0 }
        a.by_ext[f.ext or "?"] = x
        x.n, x.tin, x.tout, x.cost =
          x.n + 1, x.tin + (f.tokens_in or 0), x.tout + (f.tokens_out or 0), x.cost + (f.cost or 0)
        x.failed = x.failed + (f.state == "failed" and 1 or 0)
        local m = a.by_model[f.model or "?"] or { n = 0, failed = 0, cost = 0 }
        a.by_model[f.model or "?"] = m
        m.n, m.cost = m.n + 1, m.cost + (f.cost or 0)
        m.failed = m.failed + (f.state == "failed" and 1 or 0)
      end
    elseif e.kind == "agent.run" then
      local x = a.actions[e.action or "?"] or { n = 0, error = 0, cost = 0, calls = 0, escalated = 0, cached = 0 }
      a.actions[e.action or "?"] = x
      x.n, x.cost, x.calls = x.n + 1, x.cost + (e.cost or 0), x.calls + (e.calls or 1)
      x.error = x.error + (e.outcome == "error" and 1 or 0)
      x.escalated = x.escalated + (e.escalated and 1 or 0)
      x.cached = x.cached + (e.cached and 1 or 0)
    elseif e.kind == "agent.decision" then
      local d = a.decisions[e.action or "?"] or { accepted = 0, rejected = 0, other = 0 }
      a.decisions[e.action or "?"] = d
      local key = (e.decision == "accepted" or e.decision == "rejected") and e.decision or "other"
      d[key] = d[key] + 1
    end
  end
  return a
end

--- The report as Markdown lines
---@param events table[]
---@param root_name string?
---@return string[]
function M.render(events, root_name)
  local a = M.aggregate(events)
  local out = { "# Leader · " .. (root_name or "this project"), "" }
  if #events == 0 then
    vim.list_extend(out, {
      "Nothing recorded yet. A build (`<leader>aSbb`) writes here when it ends; agent actions are recorded too once this folder exists.",
      "",
      "Everything stays on this machine: `.leader/README.md` says what is recorded and what never is.",
    })
    return out
  end
  if a.span.from then
    out[#out + 1] = ("%d events · %s to %s · only on this machine"):format(
      #events,
      os.date("%Y-%m-%d", a.span.from),
      os.date("%Y-%m-%d", a.span.to)
    )
    out[#out + 1] = ""
  end

  local nb = #a.builds
  if nb > 0 then
    out[#out + 1] = "## Builds"
    out[#out + 1] = ""
    local words = {}
    for _, o in ipairs(ranked(a.outcomes)) do
      words[#words + 1] = ("%d %s"):format(o.n, o.key)
    end
    out[#out + 1] = ("- %d builds: %s"):format(nb, table.concat(words, ", "))
    out[#out + 1] = ("- cost %s in total, %s a build · %.0fs a build"):format(
      usd(a.cost),
      usd(a.cost / nb),
      a.seconds / nb
    )
    out[#out + 1] = ("- %s needed fix rounds (%.1f on average when they did)"):format(
      pct(a.fix_builds, nb),
      a.fix_builds > 0 and a.fix_rounds / a.fix_builds or 0
    )
    if a.req_total > 0 then
      out[#out + 1] = ("- requirements with a test: %s (%d of %d, summed over builds) · %d placeholders · %d lost a test"):format(
        pct(a.req_proven, a.req_total),
        a.req_proven,
        a.req_total,
        a.placeholders,
        a.regressions
      )
    end
    out[#out + 1] = ""
    local failing = ranked(a.failing)
    if #failing > 0 then
      out[#out + 1] = "## What fails"
      out[#out + 1] = ""
      for i, f in ipairs(failing) do
        if i > 8 then
          break
        end
        out[#out + 1] = ("- `%s` failed in %d of %d builds that ran it (%s)"):format(
          f.key,
          f.n,
          a.check_runs[f.key],
          pct(f.n, a.check_runs[f.key])
        )
      end
      out[#out + 1] = ""
    end
    if next(a.by_ext) then
      out[#out + 1] = "## Files by kind"
      out[#out + 1] = ""
      for _, e in
        ipairs(ranked(vim.tbl_map(function(x)
          return x.n
        end, a.by_ext)))
      do
        local x = a.by_ext[e.key]
        out[#out + 1] = ("- `.%s`: %d files · %d failed · %d→%d tokens a file · %s a file"):format(
          e.key,
          x.n,
          x.failed,
          x.tin / x.n,
          x.tout / x.n,
          usd(x.cost / x.n)
        )
      end
      out[#out + 1] = ""
    end
    if next(a.by_model) then
      out[#out + 1] = "## Models (files written)"
      out[#out + 1] = ""
      for _, m in
        ipairs(ranked(vim.tbl_map(function(x)
          return x.n
        end, a.by_model)))
      do
        local x = a.by_model[m.key]
        out[#out + 1] = ("- `%s`: %d files · %s failed · %s a file"):format(
          m.key,
          x.n,
          pct(x.failed, x.n),
          usd(x.cost / x.n)
        )
      end
      out[#out + 1] = ""
    end
  end

  if next(a.actions) then
    out[#out + 1] = "## Agent actions"
    out[#out + 1] = ""
    for _, e in
      ipairs(ranked(vim.tbl_map(function(x)
        return x.n
      end, a.actions)))
    do
      local x = a.actions[e.key]
      local d = a.decisions[e.key] or { accepted = 0, rejected = 0, other = 0 }
      local decided = d.accepted + d.rejected
      out[#out + 1] = ("- `%s`: %d runs · %s errors · %s accepted of %d decided · %.1f calls a run · %s a run%s"):format(
        e.key,
        x.n,
        pct(x.error, x.n),
        pct(d.accepted, decided),
        decided,
        x.calls / x.n,
        usd(x.cost / x.n),
        x.escalated > 0 and (" · %d escalated"):format(x.escalated) or ""
      )
    end
    out[#out + 1] = ""
  end
  out[#out + 1] = "The folder is `.leader/` at the project root. Delete it to clear everything."
  return out
end

return M
