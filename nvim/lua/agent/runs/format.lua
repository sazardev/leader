-- ── Shared history formats ───────────────────────────────────────────────────
local M = {}

---@param usd number?
---@return string
function M.money(usd)
  if not usd then
    return "—"
  end
  return usd >= 1 and ("$%.2f"):format(usd) or ("$%.4f"):format(usd)
end

---@param n number?
---@return string
function M.tokens(n)
  if not n then
    return "—"
  end
  return n >= 1000 and ("%.1fk"):format(n / 1000) or tostring(n)
end

---@param ms number?
---@return string
function M.seconds(ms)
  return ms and ("%.1fs"):format(ms / 1000) or "—"
end

local ICON = {
  accepted = "✓",
  rejected = "✗",
  discarded = "⊘",
  unchanged = "=",
  pending = "◌",
  findings = "◆",
  shown = "•",
  error = "!",
  cancelled = "■",
}

---@param run table
---@return string
function M.icon(run)
  return ICON[run.outcome] or "?"
end

--- "accepted", "3 findings"...
---@param run table
---@return string
function M.outcome(run)
  if run.outcome == "findings" then
    return ("%s finding%s"):format(tostring(run.detail or 0), run.detail == 1 and "" or "s")
  end
  return run.outcome
end

---@param run table
---@return string "orders.go:5-12 Total"
function M.target(run)
  if run.output == "oneshot" then
    return run.name or run.action -- a call with no code of its own: the commit draft, the staged review, a plan
  end
  local range = run.first == run.last and tostring(run.first) or ("%d-%d"):format(run.first or 0, run.last or 0)
  return ("%s:%s%s"):format(vim.fn.fnamemodify(run.file or "?", ":t"), range, run.name and (" " .. run.name) or "")
end

---@param run table
---@return string "claude/sonnet"
function M.model(run)
  return (run.backend or "?") .. "/" .. (run.model or "default")
end

return M
