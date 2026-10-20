-- ── Versions (pure) ──────────────────────────────────────────────────────────
-- "1.8.0", "v1.8.0", "1.9.0-rc1": numbers first, a pre-release sorts before the release it leads to.
local M = {}

---@param text string?
---@return { [1]: integer, [2]: integer, [3]: integer, pre: string? }?
function M.parse(text)
  if type(text) ~= "string" then
    return nil
  end
  local major, minor, patch, pre = vim.trim(text):match "^v?(%d+)%.(%d+)%.(%d+)%-?([%w%.]*)$"
  if not major then
    return nil
  end
  return { tonumber(major), tonumber(minor), tonumber(patch), pre = pre ~= "" and pre or nil }
end

--- -1, 0 or 1; nil when either is not a version.
---@param a string
---@param b string
---@return integer?
function M.compare(a, b)
  local x, y = M.parse(a), M.parse(b)
  if not (x and y) then
    return nil
  end
  for i = 1, 3 do
    if x[i] ~= y[i] then
      return x[i] < y[i] and -1 or 1
    end
  end
  if x.pre == y.pre then
    return 0
  end
  if not x.pre then
    return 1
  elseif not y.pre then
    return -1
  end
  return x.pre < y.pre and -1 or 1
end

---@param candidate string?
---@param current string?
---@return boolean candidate is a version newer than current
function M.newer(candidate, current)
  return candidate ~= nil and current ~= nil and M.compare(candidate, current) == 1
end

--- "v1.8.0" → "1.8.0"
---@param text string
---@return string
function M.clean(text)
  return (vim.trim(text):gsub("^v", ""))
end

return M
