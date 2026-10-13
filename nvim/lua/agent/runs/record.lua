-- ── De un trabajo a un registro ──────────────────────────────────────────────
-- Siempre guarda las métricas (tokens, coste, tamaños); el texto (prompt y respuesta, que incluyen
-- tu código) solo con `settings.agent.history.store_text`.
local jobs = require "agent.jobs"
local settings = require("core.settings").agent.history

local M = {}

---@param job AgentJob
---@param status "done"|"error"|"cancelled"
---@param err string?
---@return table
function M.build(job, status, err)
  local usage = (job.result and job.result.usage) or {}
  local context, context_chars = {}, 0
  for _, s in ipairs(job.sections or {}) do
    context[#context + 1] = { name = s.name, chars = #s.text }
    context_chars = context_chars + #s.text
  end

  local ts = os.time()
  local entry = {
    t = "run",
    id = ("%d-%d"):format(vim.uv.hrtime() / 1e6 % 1e9, job.id), -- único entre sesiones sin depender del reloj
    ts = ts,
    action = job.action.name,
    output = job.action.output,
    backend = job.selection.backend,
    model = job.selection.model,
    tier = job.selection.tier,
    effort = job.selection.effort,
    status = status,
    error = err,
    ms = math.floor(jobs.elapsed(job) * 1000),
    cwd = vim.fn.getcwd(),
    file = job.target.path,
    lang = job.target.lang,
    kind = job.target.kind,
    name = job.target.name,
    first = job.target.first,
    last = job.target.last,
    has_input = job.input ~= nil,
    usage = {
      tokens_in = usage.tokens_in,
      tokens_out = usage.tokens_out,
      cache_read = usage.cache_read,
      cache_write = usage.cache_write,
      cost = usage.cost,
    },
    context = context,
    chars = {
      system = #(job.system or ""),
      message = #(job.prompt or ""),
      target = #table.concat(job.target.lines, "\n"),
      context = context_chars,
    },
  }
  if settings.store_text then
    entry.input = job.input
    entry.system = job.system
    entry.prompt = job.prompt
    entry.response = job.result and job.result.text or job.partial
  end
  return entry
end

return M
