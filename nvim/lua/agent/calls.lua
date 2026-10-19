-- ── One-shot calls in flight ─────────────────────────────────────────────────
-- What `oneshot.lua` runs has no buffer to paint a spinner in (the project documents, commit draft, staged review, plans):
-- this registry knows what is running and the statusline shows it as a badge ("⠹ drawing screens"). Pure state (no UI,
-- no processes): oneshot reports, the statusline reads. When one ends, ✓/✗ and its label stay for a few seconds, so a
-- request that finished while you were looking elsewhere is not missed.
local M = {}

local FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local OUTCOME_MS = 4000

---@class AgentCall
---@field id integer
---@field label string
---@field model string?
---@field t0 integer
---@field handle vim.SystemObj?
---@field cancelled boolean?
---@field quiet boolean? has its own indicator (the build): not shown here

---@type table<integer, AgentCall>
local running = {}
local seq = 0

---@type { text: string, ok: boolean, at: integer }?
local outcome

--- "kit_screens" → "screens", "plan_step" → "plan step"
---@param action string
---@return string
local function label_of(action)
  return (action:gsub("^kit_", ""):gsub("_", " "))
end

---@param req { action: string, label: string?, quiet: boolean? }
---@param model string?
---@return AgentCall
function M.start(req, model)
  seq = seq + 1
  local call = {
    id = seq,
    label = req.label or label_of(req.action),
    model = model,
    t0 = vim.uv.hrtime(),
    quiet = req.quiet,
  }
  running[call.id] = call
  return call
end

---@param call AgentCall
---@param ok boolean
function M.finish(call, ok)
  running[call.id] = nil
  if call.quiet or call.cancelled then
    return
  end
  outcome = {
    text = ("%s %s"):format(ok and "✓" or "✗", call.label),
    ok = ok,
    at = vim.uv.hrtime(),
  }
end

---@return AgentCall[] the ones the statusline shows, oldest first
function M.running()
  local list = vim.tbl_filter(function(c)
    return not c.quiet
  end, vim.tbl_values(running))
  table.sort(list, function(a, b)
    return a.id < b.id
  end)
  return list
end

--- Kills every running call (their callbacks answer "cancelled")
---@return integer how many
function M.cancel()
  local n = 0
  for _, call in pairs(running) do
    call.cancelled = true
    if call.handle then
      pcall(call.handle.kill, call.handle, 15)
    end
    n = n + 1
  end
  return n
end

--- " ⠹ drawing screens " while running; " ✓ drawing screens " for a few seconds after; "" otherwise
---@return string
function M.statusline()
  local list = M.running()
  if #list > 0 then
    local frame = FRAMES[math.floor(vim.uv.hrtime() / 1e8) % #FRAMES + 1]
    return (" %s %s "):format(frame, #list == 1 and list[1].label or (#list .. " requests"))
  end
  if outcome and (vim.uv.hrtime() - outcome.at) / 1e6 < OUTCOME_MS then
    return (" %s "):format(outcome.text)
  end
  return ""
end

--- Highlight of the statusline text: the blue chip while running, green when it worked, the failed chip (the one Dart's
--- tools use) when it did not
---@return string
function M.statusline_group()
  if #M.running() > 0 then
    return "AgentStatus"
  end
  return outcome and not outcome.ok and "DartgenFailed" or "AgentDone"
end

return M
