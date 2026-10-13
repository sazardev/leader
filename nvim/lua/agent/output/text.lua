-- "text" presenter: the response in a window next to the code (explain, ask)
local anchor = require "agent.anchor"
local float = require "agent.ui.float"
local jobs = require "agent.jobs"
local selection = require "agent.selection"
local runs = require "agent.runs"
local stats = require "agent.stats"
local text = require "agent.text"

local M = {}

---@param job AgentJob
---@return string
local function title(job, suffix)
  return ("%s · %s · %s"):format(job.action.label, selection.label(job.selection), suffix)
end

---@param job AgentJob
function M.stream(job)
  float.show(job, job.partial, title(job, ("%.0fs…"):format(jobs.elapsed(job))))
end

---@param job AgentJob
---@param result table
function M.done(job, result)
  float.show(job, text.trim(result.text), title(job, stats.line(job, result)))
  float.autoclose(job)
  anchor.delete(job.buf, job.anchor)
  runs.event(job, "shown")
end

---@param job AgentJob
function M.release(job)
  float.discard(job)
  anchor.delete(job.buf, job.anchor)
end

return M
