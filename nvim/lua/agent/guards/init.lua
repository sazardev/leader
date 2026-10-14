-- ── Guards: checks before a request ──────────────────────────────────────────
-- A guard looks at a request that is about to be made and answers nothing (all good), `block` (it must not happen) or
-- `confirm` (ask first). They run in order; the first block wins; every confirm is asked. Contract of each guard file:
--
--   check(req) -> nil | { level = "block"|"confirm", title = string, message = string?, lines = (string|table)[] }
--     message: what the notification says when it blocks; lines: the modal's body when it asks
--     req = { action = string, backend = string?, model = string?, chars = integer, count = integer?,
--             preapproved = boolean? }       (`preapproved`: the user already confirmed this exact spend, e.g. a batch)
--
-- Add a guard: one file here + its name in NAMES. The pipeline only knows `guards.check`.
local M = {}

local NAMES = { "budget" }

---@param req table
---@return { level: string, title: string, message: string?, lines: table }[] verdicts
local function verdicts(req)
  local out = {}
  for _, name in ipairs(NAMES) do
    local ok, v = pcall(function()
      return require("agent.guards." .. name).check(req)
    end)
    if ok and v then
      out[#out + 1] = v
    end
  end
  return out
end

---@param req table
---@param proceed fun() everything is fine, or the user said yes to every question
---@param deny fun(why: string?) a guard blocked it, or the user said no
function M.check(req, proceed, deny)
  local list = verdicts(req)
  for _, v in ipairs(list) do
    if v.level == "block" then
      require("utils.log").warn("Agent: " .. (v.message or v.title))
      return deny(v.title)
    end
  end
  local asks = vim.tbl_filter(function(v)
    return v.level == "confirm"
  end, list)
  if #asks == 0 then
    return proceed()
  end
  -- one modal with every reason, not one per guard
  local lines = {}
  for _, v in ipairs(asks) do
    vim.list_extend(lines, v.lines)
  end
  require("utils.modal").confirm(lines, {
    title = asks[1].title,
    on_cancel = function()
      deny "cancelled"
    end,
  }, proceed)
end

return M
