-- ── One more attempt, with the errors in hand ────────────────────────────────
-- When accepted code made things worse, the retry is a batch over the functions that hold the NEW problems, run with the
-- `fix regression` action. It asks first (what it would cost, which attempt it is) unless `auto_retry` says not to, and it
-- stops after `max_retries` attempts in a chain: the attempt counter travels in the job's `meta` from one proposal to the next.
local regressions = require "agent.verify.regressions"

local M = {}

---@class AgentRetryCtx
---@field buf integer
---@field diagnostics table[]            the NEW problems (diagnostic-like: lnum 0-based, severity, message, source)
---@field job AgentJob                   the job whose proposal was accepted
---@field source "lsp"|"build"
---@field output string?                 raw build output, handed to the model when the problems come from the build

---@param ctx AgentRetryCtx
---@return integer attempt, integer max
local function attempt_of(ctx)
  return ((ctx.job.meta or {}).attempt or 0) + 1, require("core.settings").agent.verify.max_retries
end

---@param ctx AgentRetryCtx
function M.offer(ctx)
  local cfg = require("core.settings").agent.verify
  local log = require "utils.log"
  local attempt, max = attempt_of(ctx)
  local summary = regressions.describe(ctx.diagnostics, 3)

  if attempt > max then
    return log.warn(
      ("Agent: %d new problem%s after accepting, and no attempts left (%s)"):format(
        #ctx.diagnostics,
        #ctx.diagnostics == 1 and "" or "s",
        summary[1] or ""
      )
    )
  end

  local items = require("agent.fixall").items(ctx.buf, ctx.diagnostics)
  if #items == 0 then
    return log.warn("Agent: new problems after accepting: " .. table.concat(summary, " · "))
  end
  if ctx.source == "build" and ctx.output then
    local text = require("agent.text").clip(ctx.output, 1500)
    for _, item in ipairs(items) do
      item.extra = { { name = "verify_errors", text = text } }
    end
  end

  local hl = require("utils.modal").hl
  local header = {
    {
      {
        ("%d new problem%s in the code you accepted"):format(#ctx.diagnostics, #ctx.diagnostics == 1 and "" or "s"),
        hl.warn,
      },
    },
  }
  for _, line in ipairs(summary) do
    header[#header + 1] = { { "  " .. line, hl.muted } }
  end
  header[#header + 1] = { { ("attempt %d of %d"):format(attempt, max), hl.muted } }

  local action = require("agent.verify.action").build(attempt, max)
  require("agent.batch").run {
    title = action.label,
    action = action,
    items = items,
    header = header,
    confirm = not cfg.auto_retry,
    meta = { attempt = attempt, parent = ctx.job.record_id },
  }
end

return M
