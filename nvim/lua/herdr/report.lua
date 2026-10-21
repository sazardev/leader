-- ── What nvim is doing, told to Herdr ─────────────────────────────────────────
-- Herdr shows an agent's state in its panel (idle, working, blocked). Leader is one too: while the inline agent runs it
-- says "working" and what it is doing, when a proposal waits for you it says "blocked", and when nothing runs it goes
-- back to "idle".
--
-- It hangs off the agent's events (agent/events.lua): the flow that runs a job never knows that Herdr is listening. It
-- only speaks when this nvim registered itself in Herdr (see herdr/init.lua).
local cli = require "herdr.cli"
local herdr = require "herdr"

local M = {}

local seq = 0

--- `--seq` must grow between reports
---@return string
local function next_seq()
  seq = seq + 1
  return tostring(os.time() * 1000 + seq)
end

--- Tells Herdr what this nvim is doing
---@param state "idle"|"working"|"blocked"
---@param message string?
function M.report(state, message)
  local pane = herdr.pane_id()
  if not pane or not herdr.registered() then
    return
  end
  local args = {
    "pane",
    "report-agent",
    pane,
    "--source",
    "nvim",
    "--agent",
    "nvim",
    "--state",
    state,
    "--seq",
    next_seq(),
  }
  if message and message ~= "" then
    vim.list_extend(args, { "--message", message:sub(1, 200) })
  end
  cli.json(args, function() end) -- what herdr says about it does not matter
end

--- Is a proposal waiting for the user?
---@return boolean
local function waiting()
  local ok, replace = pcall(require, "agent.output.replace")
  if not ok then
    return false
  end
  return #replace.pending() > 0
end

--- What the job is doing, in a few words
---@param job table
---@return string
local function what(job)
  local action = job.action or {}
  local name = action.desc or action.label or "working"
  local target = job.target or {}
  local where = target.path or (target.buf and vim.api.nvim_buf_get_name(target.buf))
  if where and where ~= "" then
    return ("%s · %s"):format(name, vim.fn.fnamemodify(where, ":t"))
  end
  return name
end

--- Subscribes to the agent's events
function M.setup()
  local events = require "agent.events"
  events.on("job.started", function(payload)
    M.report("working", what(payload.job))
  end)
  events.on("job.settled", function()
    if waiting() then
      M.report("blocked", "waiting for you to accept a proposal")
    else
      M.report("idle")
    end
  end)
end

return M
