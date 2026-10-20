-- ── Running a job ────────────────────────────────────────────────────────────
-- Launches the backend process, streams the text to the presenter and
-- closes the job (success, failure, timeout or cancellation). It knows nothing about
-- Claude or OpenCode: only the agent/backends contract.
local anchor = require "agent.anchor"
local backends = require "agent.backends"
local events = require "agent.events"
local jobs = require "agent.jobs"
local log = require "utils.log"
local runs = require "agent.runs"
local settings = require("core.settings").agent
local stats = require "agent.stats"
local status = require "agent.ui.status"
local text = require "agent.text"

local M = {}

---@param job AgentJob
---@param err string
local function fail(job, err)
  job.state = "error"
  jobs.finish(job)
  runs.record(job, "error", err)
  status.clear(job)
  if job.presenter.release then
    job.presenter.release(job)
  else
    anchor.delete(job.buf, job.anchor)
  end
  log.error(("Agent %s: %s"):format(job.action.label, text.clip(err or "unknown error", 400)))
  events.emit("job.settled", { job = job, outcome = "error" })
end

---@param job AgentJob
---@param parser table
---@param data string
local function on_data(job, parser, data)
  if job.state ~= "running" then
    return
  end
  local piece = parser.feed(data)
  if piece then
    job.partial = job.partial .. piece
    if job.presenter.stream then
      M.stream_soon(job)
    end
  end
end

--- Draws the partial text at most once every `settings.stream_ms` per job: a model streaming token by token (or several
--- agents at once) would otherwise redraw the whole answer on every chunk. The first chunk draws at once, the rest
--- coalesce into one trailing draw; the final text is always drawn by the presenter's `done`.
---@param job AgentJob
function M.stream_soon(job)
  local gap = (settings.stream_ms or 40) * 1e6
  local now = vim.uv.hrtime()
  local since = now - (job.streamed_at or 0)
  if since >= gap then
    job.streamed_at = now
    return job.presenter.stream(job)
  end
  if job.stream_timer then
    return -- one trailing draw is already waiting
  end
  job.stream_timer = true
  vim.defer_fn(function()
    job.stream_timer = nil
    if job.state == "running" then
      job.streamed_at = vim.uv.hrtime()
      job.presenter.stream(job)
    end
  end, math.ceil((gap - since) / 1e6))
end

---@param job AgentJob
---@param parser table
---@param out vim.SystemCompleted
local function on_exit(job, parser, out)
  if job.state ~= "running" then
    return -- cancelled
  end
  status.clear(job)

  local result = parser.finish(out.code, out.stderr or "")
  -- vim.system kills the process with SIGTERM when the deadline expires: depending on the platform it arrives as
  -- code 124, 143 (128+15) or signal 15; if nobody cancelled (the state is still "running"), it is the deadline
  local killed = out.code == 124 or out.code == 143 or out.signal == 15
  if killed and not result.ok then
    result = { ok = false, err = ("timed out (%gs)"):format(settings.timeout_ms / 1000) }
  end
  if not result.ok then
    return fail(job, result.err)
  end

  require("agent.cache").store(job, result)
  M.settle(job, result)
end

--- A call that succeeded: record it, hand the result to the presenter, announce it. Also what a cache hit goes through,
--- so an answer from disk looks the same as one from the model, except that it is NOT a run: no model was called, so it
--- stays out of the history and the spend report (the cache keeps its own counters).
---@param job AgentJob
---@param result table
function M.settle(job, result)
  job.state, job.result = "done", result
  jobs.finish(job)
  if not result.cached then
    runs.record(job, "done") -- before the presenter: its events (accepted, rejected...) hang off this record
  end
  local ok, summary = pcall(job.presenter.done, job, result)
  if not ok then
    anchor.delete(job.buf, job.anchor)
    return log.error("Agent: " .. tostring(summary))
  end
  if summary then
    status.summary(job, ("✓ %s · %s"):format(summary, stats.line(job, result)))
  end
  events.emit("job.settled", { job = job, outcome = "done" })
end

---@param job AgentJob
function M.run(job)
  local backend = backends.get(job.selection.backend)
  local spec = backend.build {
    system = job.system,
    prompt = job.prompt,
    model = job.selection.model,
    effort = job.selection.effort,
    action = job.action.name,
  }
  local parser = backend.parser()
  -- `cwd` does not update $PWD, and some CLIs (opencode) resolve their project from it: without this they load
  -- the AGENTS.md/CLAUDE.md of the repo nvim was launched from (~10k tokens) instead of the neutral directory
  local env = spec.cwd and vim.tbl_extend("force", { PWD = spec.cwd }, spec.env or {}) or spec.env

  local ok, handle = pcall(vim.system, spec.cmd, {
    stdin = spec.stdin,
    cwd = spec.cwd,
    env = env,
    text = true,
    timeout = settings.timeout_ms,
    stdout = function(_, data)
      if data then
        vim.schedule(function()
          on_data(job, parser, data)
        end)
      end
    end,
  }, function(out)
    vim.schedule(function()
      on_exit(job, parser, out)
    end)
  end)

  if not ok then
    return fail(job, tostring(handle))
  end
  job.handle = handle
end

---@param job AgentJob
function M.cancel(job)
  if job.state ~= "running" then
    return
  end
  job.state = "cancelled"
  if job.handle then
    job.handle:kill(15)
  end
  jobs.finish(job)
  runs.record(job, "cancelled")
  status.clear(job)
  if job.presenter.release then
    job.presenter.release(job)
  else
    anchor.delete(job.buf, job.anchor)
  end
  events.emit("job.settled", { job = job, outcome = "cancelled" })
end

--- A guard stopped it before anything was sent (the budget, or you said no to a question): nothing to record, nothing spent
---@param job AgentJob
function M.deny(job)
  if job.state ~= "running" then
    return
  end
  job.state = "cancelled"
  jobs.finish(job)
  status.clear(job)
  if job.presenter.release then
    job.presenter.release(job)
  else
    anchor.delete(job.buf, job.anchor)
  end
  events.emit("job.settled", { job = job, outcome = "denied" })
end

return M
