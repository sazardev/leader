-- ── Pure text helpers ────────────────────────────────────────────────────────
local M = {}

---@param s string?
---@return string
function M.trim(s)
  local trimmed = (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
  return trimmed
end

--- Clips to `max` characters, cutting at a line break if possible
---@param s string
---@param max integer
---@return string
function M.clip(s, max)
  if #s <= max then
    return s
  end
  local cut = s:sub(1, max)
  local nl = cut:match ".*()\n"
  return (nl and nl > max * 0.5 and cut:sub(1, nl - 1) or cut) .. "\n…"
end

---@param n number?
---@return string
function M.tokens(n)
  if not n then
    return ""
  end
  return n >= 1000 and ("%.1fk"):format(n / 1000) or tostring(n)
end

return M
