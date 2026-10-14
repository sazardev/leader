-- ── From plan steps to batch pieces ──────────────────────────────────────────
-- Each chosen step becomes a piece: the target is the declaration it names (found again NOW, the files may have moved since
-- the plan was made), the step's text is its instruction, and its context says where it stands in the plan and carries what
-- the steps before it proposed, so step 3 uses the field that step 1 adds.
local locate = require "agent.plan.locate"
local text = require "agent.text"

local M = {}

local EARLIER_MAX_CHARS = 1500 -- per earlier step
local EARLIER_STEPS = 3 -- how many of the steps before are shown in full

--- The plan as the model sees it from step `k`
---@param instruction string
---@param chosen table[]
---@param k integer
---@return string
function M.plan_text(instruction, chosen, k)
  local lines = {}
  for i, s in ipairs(chosen) do
    lines[#lines + 1] = ("%d. %s · %s — %s%s"):format(
      i,
      s.path,
      s.symbol,
      s.what,
      i == k and "   <- THIS STEP" or ""
    )
  end
  return ("Overall change: %s\nSteps (do only the marked one; earlier steps are already proposed, later ones come after):\n%s"):format(
    instruction,
    table.concat(lines, "\n")
  )
end

--- The code earlier steps proposed (the last few), so a later step builds on it
---@param chosen table[]
---@param done AgentBatchItem[] pieces already finished, in order
---@return string?
function M.earlier_text(chosen, done)
  local parts = {}
  for _, item in ipairs(done) do
    local proposal = item.job and item.job.proposal
    if proposal and item.step then
      local code = text.clip(table.concat(proposal.raw or proposal.lines, "\n"), EARLIER_MAX_CHARS)
      parts[#parts + 1] = ("Step %d (%s · %s), as proposed:\n%s"):format(
        item.step.n,
        item.step.path,
        item.step.symbol,
        code
      )
    end
  end
  if #parts == 0 then
    return nil
  end
  return table.concat(vim.list_slice(parts, math.max(1, #parts - EARLIER_STEPS + 1)), "\n\n")
end

--- The declaration `step` names, in its file as it is now
---@param step table
---@return AgentTarget?, string? why
function M.target_of(step)
  local abs = step.site.abs
  local best
  for _, d in ipairs(locate.declarations(abs)) do
    if
      d.name == step.symbol
      and (not best or math.abs(d.first - step.site.first) < math.abs(best.first - step.site.first))
    then
      best = d
    end
  end
  if not best then
    return nil, ("%s is no longer in %s"):format(step.symbol, step.path)
  end
  local buf = vim.fn.bufadd(abs)
  return require("agent.context.target").of_range(buf, best.kind, best.first, best.last, best.name)
end

--- Batch items for the chosen steps (in plan order)
---@param instruction string
---@param chosen table[]
---@return AgentBatchItem[] items, string[] skipped why each skipped step was
function M.items(instruction, chosen)
  local items, skipped = {}, {}
  for k, step in ipairs(chosen) do
    local target, why = M.target_of(step)
    if target then
      items[#items + 1] = {
        label = step.symbol,
        target = target,
        input = step.what,
        step = step,
        extra = function(done)
          local sections = { { name = "plan", text = M.plan_text(instruction, chosen, k) } }
          local earlier = M.earlier_text(chosen, done)
          if earlier then
            sections[#sections + 1] = { name = "earlier_steps", text = earlier }
          end
          return sections
        end,
      }
    else
      skipped[#skipped + 1] = ("step %d: %s"):format(step.n, why or "its code cannot be edited")
    end
  end
  return items, skipped
end

return M
