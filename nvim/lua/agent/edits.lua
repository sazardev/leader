-- ── Recent edits of a buffer ─────────────────────────────────────────────────
-- What you just changed, as small hunks (old lines → new lines), so "next edit" can see the pattern you are in the
-- middle of (the rename you are following through, the field you added to one constructor and not yet to the others).
-- A baseline snapshot per file buffer is compared with the buffer each time an insert ends or a normal-mode change
-- settles: one `vim.diff`, no model, no LSP. `hunks` and `render` are pure; the rest is the small state around them.
local settings = require("core.settings").agent.next_edit

local M = {}

---@class AgentEdit
---@field line integer      1-based line where it landed (in the new text)
---@field old string[]
---@field new string[]

---@type table<integer, { snapshot: string[], ring: AgentEdit[] }>
local bufs = {}

local SIDE = 10 -- lines kept of one side of a hunk

---@param lines string[]
---@param first integer
---@param count integer
---@return string[]
local function take(lines, first, count)
  if count <= 0 then
    return {}
  end
  local out = vim.list_slice(lines, first, first + math.min(count, SIDE) - 1)
  if count > SIDE then
    out[#out + 1] = ("… (%d more lines)"):format(count - SIDE)
  end
  return out
end

--- The hunks that turn `old` into `new` (pure)
---@param old string[]
---@param new string[]
---@return AgentEdit[]
function M.hunks(old, new)
  local a = table.concat(old, "\n") .. "\n"
  local b = table.concat(new, "\n") .. "\n"
  ---@type integer[][]
  local idx = vim.diff(a, b, { result_type = "indices" }) or {}
  local out = {}
  for _, h in ipairs(idx) do
    local sa, ca, sb, cb = h[1], h[2], h[3], h[4]
    -- a pure deletion reports the line BEFORE the gap: the spot is the next one
    out[#out + 1] = { line = cb == 0 and sb + 1 or math.max(sb, 1), old = take(old, sa, ca), new = take(new, sb, cb) }
  end
  return out
end

--- The edits as the prompt shows them, oldest first, newest last, within `max_chars` (the newest win when it is tight)
---@param edits AgentEdit[]
---@param max_chars integer
---@return string
function M.render(edits, max_chars)
  local blocks, used = {}, 0
  for i = #edits, 1, -1 do
    local e = edits[i]
    local lines = { ("@@ line %d"):format(e.line) }
    for _, l in ipairs(e.old) do
      lines[#lines + 1] = "-" .. l
    end
    for _, l in ipairs(e.new) do
      lines[#lines + 1] = "+" .. l
    end
    local block = table.concat(lines, "\n")
    if used + #block > max_chars and #blocks > 0 then
      break
    end
    used = used + #block + 1
    table.insert(blocks, 1, block)
  end
  return table.concat(blocks, "\n")
end

---@param buf integer
---@return boolean
local function trackable(buf)
  return vim.api.nvim_buf_is_valid(buf)
    and vim.bo[buf].buftype == ""
    and vim.api.nvim_buf_get_name(buf) ~= ""
    and vim.api.nvim_buf_line_count(buf) <= settings.max_lines
end

--- Starts following a buffer: what it holds now is the baseline the next edits are measured against
---@param buf integer
function M.watch(buf)
  if bufs[buf] or not trackable(buf) then
    return
  end
  bufs[buf] = { snapshot = vim.api.nvim_buf_get_lines(buf, 0, -1, false), ring = {} }
end

--- Notes what changed since the last time (called when an insert ends or a change settles)
---@param buf integer
function M.record(buf)
  local st = bufs[buf]
  if not st then
    return M.watch(buf)
  end
  if not trackable(buf) then
    bufs[buf] = nil
    return
  end
  local now = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for _, h in ipairs(M.hunks(st.snapshot, now)) do
    st.ring[#st.ring + 1] = h
  end
  while #st.ring > settings.keep do
    table.remove(st.ring, 1)
  end
  st.snapshot = now
end

--- Edits of a buffer, oldest first (it brings its pending changes up to date first)
---@param buf integer
---@return AgentEdit[]
function M.get(buf)
  if bufs[buf] then
    M.record(buf)
  end
  return bufs[buf] and bufs[buf].ring or {}
end

---@param buf integer
function M.forget(buf)
  bufs[buf] = nil
end

--- Forgets everything (tests)
function M.reset()
  bufs = {}
end

return M
