-- ── Did the change make things worse? ────────────────────────────────────────
-- Pure comparison of the diagnostics a buffer had BEFORE a proposal was accepted and AFTER. A diagnostic is identified by
-- what it says (source, code, message), not by where it is: the accepted code moves lines around, and the same old
-- warning one line lower is not a new one. It is a multiset: three identical errors before and four after is one new.
local M = {}

---@param name string "error" | "warn"
---@return integer
function M.severity_number(name)
  return name == "warn" and vim.diagnostic.severity.WARN or vim.diagnostic.severity.ERROR
end

---@param d table
---@return string
function M.fingerprint(d)
  return table.concat({ d.source or "", tostring(d.code or ""), d.message or "" }, "\0")
end

--- The diagnostics in `after` that were not in `before`, at or above `max_severity` (ERROR = 1, WARN = 2)
---@param before table[]
---@param after table[]
---@param max_severity integer
---@return table[]
function M.new(before, after, max_severity)
  local counts = {}
  for _, d in ipairs(before) do
    if (d.severity or 4) <= max_severity then
      local fp = M.fingerprint(d)
      counts[fp] = (counts[fp] or 0) + 1
    end
  end
  local out = {}
  for _, d in ipairs(after) do
    if (d.severity or 4) <= max_severity then
      local fp = M.fingerprint(d)
      if (counts[fp] or 0) > 0 then
        counts[fp] = counts[fp] - 1
      else
        out[#out + 1] = d
      end
    end
  end
  table.sort(out, function(a, b)
    return a.lnum < b.lnum
  end)
  return out
end

--- Short lines to show: `L12 undefined: x`
---@param list table[]
---@param limit integer
---@return string[]
function M.describe(list, limit)
  local out = {}
  for i, d in ipairs(list) do
    if i > limit then
      out[#out + 1] = ("… and %d more"):format(#list - limit)
      break
    end
    out[#out + 1] = ("L%d %s"):format(d.lnum + 1, (d.message or ""):gsub("\n.*", ""))
  end
  return out
end

return M
