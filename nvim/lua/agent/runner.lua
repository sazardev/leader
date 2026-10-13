-- ── Ejecución de un trabajo ──────────────────────────────────────────────────
-- Lanza el proceso del backend, le pasa el texto en streaming al presentador y
-- cierra el trabajo (éxito, fallo, tiempo agotado o cancelación). No sabe nada de
-- Claude ni de OpenCode: solo del contrato de agent/backends.
local anchor = require "agent.anchor"
local backends = require "agent.backends"
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
  log.error(("Agent %s: %s"):format(job.action.label, text.clip(err or "error desconocido", 400)))
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
      job.presenter.stream(job)
    end
  end
end

---@param job AgentJob
---@param parser table
---@param out vim.SystemCompleted
local function on_exit(job, parser, out)
  if job.state ~= "running" then
    return -- cancelado
  end
  status.clear(job)

  local result = parser.finish(out.code, out.stderr or "")
  -- vim.system mata el proceso con SIGTERM al vencer el plazo: según la plataforma llega como
  -- código 124, 143 (128+15) o señal 15; si nadie canceló (el estado sigue "running"), es el plazo
  local killed = out.code == 124 or out.code == 143 or out.signal == 15
  if killed and not result.ok then
    result = { ok = false, err = ("timed out (%gs)"):format(settings.timeout_ms / 1000) }
  end
  if not result.ok then
    return fail(job, result.err)
  end

  job.state, job.result = "done", result
  jobs.finish(job)
  runs.record(job, "done") -- antes del presentador: sus eventos (aceptada, rechazada...) cuelgan de este registro
  local ok, summary = pcall(job.presenter.done, job, result)
  if not ok then
    anchor.delete(job.buf, job.anchor)
    return log.error("Agent: " .. tostring(summary))
  end
  if summary then
    status.summary(job, ("✓ %s · %s"):format(summary, stats.line(job, result)))
  end
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

  local ok, handle = pcall(vim.system, spec.cmd, {
    stdin = spec.stdin,
    cwd = spec.cwd,
    env = spec.env,
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
end

return M
