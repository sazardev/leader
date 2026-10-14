-- ── Diagnostics grouped by the code they live in ─────────────────────────────
-- Three findings in the same function are ONE request, not three: the model fixes them together (they usually share a
-- cause) and the input is paid once. Pure: the "which function is this line in" question is a function the caller
-- passes in (treesitter in the editor, a table in the tests).
local M = {}

---@class AgentDiag
---@field lnum integer       0-based, as vim.diagnostic
---@field end_lnum integer?
---@field severity integer
---@field message string
---@field source string?

---@class AgentDiagGroup
---@field first integer      1-based
---@field last integer
---@field name string?
---@field kind string
---@field diags AgentDiag[]

local ADJACENT = 2 -- lines apart that still count as the same place (outside any function)

--- Groups `diags` by the scope that contains them; lines outside any scope merge when they sit next to each other.
--- Result sorted from the BOTTOM of the file up: accepting one proposal then never moves the next one.
---@param diags AgentDiag[]
---@param resolve fun(line: integer): { first: integer, last: integer, name: string?, kind: string }? 1-based line → its scope
---@return AgentDiagGroup[]
function M.by_scope(diags, resolve)
  local scoped, loose = {}, {}
  for _, d in ipairs(diags) do
    local line = d.lnum + 1
    local scope = resolve(line)
    if scope then
      local key = scope.first .. "-" .. scope.last
      scoped[key] = scoped[key]
        or { first = scope.first, last = scope.last, name = scope.name, kind = scope.kind, diags = {} }
      table.insert(scoped[key].diags, d)
    else
      loose[#loose + 1] = d
    end
  end

  local groups = vim.tbl_values(scoped)

  table.sort(loose, function(a, b)
    return a.lnum < b.lnum
  end)
  local current
  for _, d in ipairs(loose) do
    local first, last = d.lnum + 1, (d.end_lnum or d.lnum) + 1
    if current and first <= current.last + ADJACENT then
      current.last = math.max(current.last, last)
      table.insert(current.diags, d)
    else
      current = { first = first, last = last, kind = "lines", diags = { d } }
      groups[#groups + 1] = current
    end
  end

  table.sort(groups, function(a, b)
    return a.first > b.first
  end)
  return groups
end

--- Keeps the diagnostics at or above a severity (vim.diagnostic.severity: ERROR = 1 … HINT = 4)
---@param diags AgentDiag[]
---@param max_severity integer the least severe that is kept
---@return AgentDiag[]
function M.at_least(diags, max_severity)
  return vim.tbl_filter(function(d)
    return (d.severity or 4) <= max_severity
  end, diags)
end

--- "error" | "warn" | "info" → the number the filter wants
---@param name string
---@return integer
function M.severity_number(name)
  local sev = vim.diagnostic.severity
  return ({ error = sev.ERROR, warn = sev.WARN, info = sev.INFO, hint = sev.HINT })[name] or sev.WARN
end

return M
