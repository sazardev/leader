-- ── Chat text utilities (pure) ───────────────────────────────────────────────
-- Everything that turns model/user text into display-safe text. No editor
-- state: tests can require this module alone.
local M = {}

--- CRLF/CR → LF and trailing whitespace kept (code is significant).
---@param s string?
---@return string
function M.normalize(s)
  s = (s or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
  return s
end

--- Removes ANSI escapes a model sometimes emits (colors, cursor movement).
---@param s string
---@return string
function M.strip_ansi(s)
  return (s:gsub("\27%[[%d;?]*[ -/]*[@-~]", ""))
end

--- Control characters that would break a buffer line (NUL, bell, vertical tab…);
--- tab, newline and carriage return are kept (CR is normalized to LF later).
---@param s string
---@return string
function M.strip_control(s)
  return (s:gsub("[%z\1-\8\11\12\14-\31\127]", ""))
end

--- Normalize + strip escapes and control characters: what the transcript and
--- the clipboard show.
---@param s string?
---@return string
function M.clean(s)
  return M.strip_control(M.strip_ansi(M.normalize(s)))
end

--- Display rows a line occupies at `width` columns (tabs and wide chars count
--- as they are drawn). Never returns 0.
---@param line string
---@param width integer
---@return integer
function M.rows(line, width)
  width = math.max(1, width or 1)
  return math.max(1, math.ceil(vim.fn.strdisplaywidth(line or "") / width))
end

--- Wrapped height of a set of lines at `width`.
---@param lines string[]
---@param width integer
---@return integer
function M.height(lines, width)
  local h = 0
  for _, l in ipairs(lines) do
    h = h + M.rows(l, width)
  end
  return math.max(1, h)
end

--- Leading/trailing whitespace removed.
---@param s string?
---@return string
function M.trim(s)
  return ((s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Clips to `max` characters, cutting at a line break when possible.
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

--- 1234 → "1.2k"; nil → ""
---@param n integer?
---@return string
function M.tokens(n)
  if not n then
    return ""
  end
  return n >= 1000 and ("%.1fk"):format(n / 1000) or tostring(n)
end

return M
