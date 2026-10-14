-- Which-key labels without the section the menu already shows: inside "Go" the entry
-- "Go run" reads "run". Display only: the keymap `desc` keeps its section as first word
-- (the cheatsheet groups by it).
local M = {}

-- NvChad's lowercase prefixes carry no information ("telescope find files")
local NOISE = { telescope = true, general = true, lsp = true }

---@param s string
---@return string[]
local function words(s)
  local t = {}
  for w in s:gmatch "%S+" do
    t[#t + 1] = w
  end
  return t
end

--- Is `word` something the group's name already says? Same word, or its stem ("test" in
--- "Tests", "comment" in "Comments"). Symbols never match.
local function said(known, word)
  local w = word:lower():gsub("[^%w]+$", "")
  if not w:find "^%w" then
    return false
  end
  if known[w] then
    return true
  end
  if #w >= 3 then
    for k in pairs(known) do
      if k:sub(1, #w) == w then
        return true
      end
    end
  end
  return false
end

--- `desc` without the words the enclosing group already says: in "Agent DDD", `"Agent ddd fix"`
--- reads `"fix"`; in "Session", `"restore session (this folder)"` reads `"restore (this folder)"`.
--- Keeps the group marker (`"+Agent DDD"` -> `"+DDD"`) and never leaves an empty label.
---@param parent? string  description of the enclosing group
---@param desc string
---@return string
function M.trim(parent, desc)
  local mark = desc:match "^%+" or ""
  local known = {}
  for _, p in ipairs(words(parent or "")) do
    known[p:lower()] = true
  end
  local kept = {}
  for i, w in ipairs(words((desc:gsub("^%+", "")))) do
    if not (said(known, w) or (i == 1 and NOISE[w:lower()])) then
      kept[#kept + 1] = w
    end
  end
  -- all words repeated: keep the label as it was
  if #kept == 0 then
    return desc
  end
  return mark .. table.concat(kept, " ")
end

--- Makes which-key apply `trim` to every item it draws. Idempotent.
function M.install()
  local view = require "which-key.view"
  if view._flat_labels then
    return
  end
  view._flat_labels = true
  local item = view.item
  view.item = function(node, opts)
    local it = item(node, opts)
    it.desc = M.trim(node.parent and node.parent.desc, it.desc)
    return it
  end
end

return M
