-- ── Historial de ejecuciones: fachada ────────────────────────────────────────
-- `record` al terminar un trabajo y `event` cuando el usuario decide (aceptar, rechazar...). Nunca
-- debe romper la acción: cualquier fallo al escribir se ignora.
local settings = require("core.settings").agent.history
local store = require "agent.runs.store"

local M = {}

local compacted = false

---@param job AgentJob
---@param status "done"|"error"|"cancelled"
---@param err string?
function M.record(job, status, err)
  if not settings.enabled then
    return
  end
  pcall(function()
    if not compacted then
      compacted = true
      store.compact()
    end
    local entry = require("agent.runs.record").build(job, status, err)
    job.record_id = entry.id
    store.append(entry)
  end)
end

---@param job AgentJob
---@param name string "accepted" | "rejected" | "discarded" | "unchanged" | "findings" | "shown"
---@param detail any?
function M.event(job, name, detail)
  if not (settings.enabled and job.record_id) then
    return
  end
  pcall(store.append, { t = "event", id = job.record_id, ts = os.time(), event = name, detail = detail })
end

return M
