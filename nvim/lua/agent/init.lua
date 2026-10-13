-- ── Agente inline: fachada pública ───────────────────────────────────────────
-- Acciones de UN disparo sobre lo que estás viendo; sin chat, sin sidebar. Cada pieza
-- vive en su carpeta, detrás de un contrato pequeño:
--
--   backends/   CLIs de agente (claude, opencode)         → añadir un backend = 1 archivo
--   actions/    recetas: objetivo, contexto, prompt, salida → añadir una acción = 1 archivo
--   context/    objetivo (treesitter) + proveedores con presupuesto (reglas, esquema, LSP...)
--   output/     presentadores: replace (diff en línea), findings (diagnósticos), text (ventana)
--   ui/         spinner, vista previa, ventana, selector, campo de texto
--   handoff/    entrega a un agente de Herdr
--   setup/      detección y puesta a punto de backends y modelos locales (Ollama, LM Studio...)
--
-- Esta fachada es lo único que usan los menús; el resto no se importa desde fuera.
local M = {}

require("agent.ui.highlights").setup()

--- Ejecuta una acción sobre el objetivo bajo el cursor (o la selección visual)
---@param name string
---@param opts { range: integer[]? }?
function M.run(name, opts)
  require("agent.pipeline").run(name, opts)
end

---@return integer cuántos trabajos se cancelaron
local function cancel_running()
  local running = require("agent.jobs").running()
  for _, job in ipairs(running) do
    require("agent.runner").cancel(job)
  end
  return #running
end

--- Cancela los trabajos en marcha
function M.cancel()
  local n = cancel_running()
  require("utils.log").info(n > 0 and ("Agent: %d cancelled"):format(n) or "Agent: nothing running")
end

--- Cancela lo que corre y descarta las propuestas pendientes del buffer. NO toca los hallazgos: son
--- diagnósticos "por atender" y sobreviven a la sesión (se quitan con `clear`).
function M.stop()
  local n = cancel_running()
  require("agent.output.replace").discard_all(vim.api.nvim_get_current_buf())
  if n > 0 then
    require("utils.log").info(("Agent: %d cancelled"):format(n))
  end
end

function M.accept()
  require("agent.output.replace").accept()
end

function M.reject()
  require("agent.output.replace").reject()
end

--- Descarta los hallazgos del agente (review y ddd review) de este archivo, también de lo guardado
function M.clear()
  require("agent.output.findings").clear(vim.api.nvim_get_current_buf())
  require("utils.log").info "Agent: findings cleared for this file"
end

--- Reabre la última respuesta (o la última propuesta, si se rechazó)
function M.last()
  local log = require "utils.log"
  local job = require("agent.jobs").last()
  if not job then
    return log.info "Agent: nothing to reopen"
  end
  if job.action.output == "text" then
    if not require("agent.ui.float").reopen() then
      log.info "Agent: nothing to reopen"
    end
  elseif job.action.output == "replace" then
    if not vim.api.nvim_buf_is_valid(job.buf) then
      return log.info "Agent: the buffer no longer exists"
    end
    job.anchor = require("agent.anchor").create(job.buf, job.target.first, job.target.last)
    job.t0 = vim.uv.hrtime() -- el tiempo mostrado es el de la llamada original, no el de ahora
    require("agent.output.replace").done(job, job.result)
  else
    log.info "Agent: the findings are already in the buffer (<leader>xd)"
  end
end

--- Pide un texto a la IA sin buffer ni objetivo (mensajes de commit...): un disparo, modelo
--- ligero por defecto. `cb(ok, texto | error)`. Devuelve el proceso, para poder cancelarlo.
---@param req { action: string, system: string, prompt: string, tier: "main"|"light"? }
---@param cb fun(ok: boolean, text: string)
---@return vim.SystemObj?
function M.complete(req, cb)
  return require("agent.oneshot").run(req, cb)
end

--- Historial de ejecuciones: prompt, respuesta, tokens y coste de cada acción
function M.history()
  require("agent.ui.history").open()
end

--- Informe de gasto agregado
function M.report()
  require("agent.ui.history").report()
end

--- Modelo principal, modelo ligero y esfuerzo, en un solo selector
function M.settings()
  require("agent.chooser").menu()
end

return M
