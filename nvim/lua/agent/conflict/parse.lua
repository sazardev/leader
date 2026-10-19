-- ── Conflict markers ─────────────────────────────────────────────────────────
-- Pure: the `<<<<<<<` / `|||||||` (diff3) / `=======` / `>>>>>>>` blocks of a text, and the resolutions that need no
-- model (both sides made the same change, or only one side changed anything). 0 tokens.
local M = {}

---@class ConflictHunk
---@field first integer    1-based line of `<<<<<<<`
---@field last integer     1-based line of `>>>>>>>`
---@field ours string[]
---@field theirs string[]
---@field base string[]?   only with `merge.conflictStyle = diff3` or `zdiff3`
---@field ours_label string
---@field theirs_label string

---@param lines string[]
---@return ConflictHunk[]
function M.parse(lines)
  local hunks = {}
  local cur, part
  for i, line in ipairs(lines) do
    if line:match "^<<<<<<<" then
      cur = {
        first = i,
        ours = {},
        theirs = {},
        ours_label = vim.trim(line:sub(8)),
        theirs_label = "",
      }
      part = "ours"
    elseif cur and line:match "^|||||||" then
      cur.base, part = {}, "base"
    elseif cur and line:match "^=======$" then
      part = "theirs"
    elseif cur and line:match "^>>>>>>>" then
      cur.last = i
      cur.theirs_label = vim.trim(line:sub(8))
      hunks[#hunks + 1] = cur
      cur, part = nil, nil
    elseif cur and part then
      table.insert(cur[part], line)
    end
  end
  return hunks
end

---@param lines string[]
---@return string[]
local function normalized(lines)
  return vim.tbl_map(function(l)
    return (l:gsub("%s+$", ""))
  end, lines)
end

--- The resolution that needs no model, and why; nil when the two sides really disagree
---@param h ConflictHunk
---@return string[]?, string?
function M.trivial(h)
  local ours, theirs = normalized(h.ours), normalized(h.theirs)
  if vim.deep_equal(ours, theirs) then
    return h.ours, "both sides made the same change"
  end
  if h.base then
    local base = normalized(h.base)
    if vim.deep_equal(ours, base) then
      return h.theirs, "only theirs changed it"
    elseif vim.deep_equal(theirs, base) then
      return h.ours, "only ours changed it"
    end
  end
  return nil, nil
end

--- The text with the trivial conflicts resolved, and how many were (pure)
---@param lines string[]
---@return string[], integer resolved, integer left
function M.resolve_trivial(lines)
  local hunks = M.parse(lines)
  local out = vim.deepcopy(lines)
  local resolved = 0
  for i = #hunks, 1, -1 do -- bottom up: the line numbers above stay valid
    local h = hunks[i]
    local text = M.trivial(h)
    if text then
      local new = {}
      for _, l in ipairs(text) do
        new[#new + 1] = l
      end
      for _ = h.first, h.last do
        table.remove(out, h.first)
      end
      for j, l in ipairs(new) do
        table.insert(out, h.first + j - 1, l)
      end
      resolved = resolved + 1
    end
  end
  return out, resolved, #hunks - resolved
end

--- Is any conflict marker left (a resolved file must have none)
---@param lines string[]
---@return boolean
function M.has_markers(lines)
  return #M.parse(lines) > 0
end

return M
