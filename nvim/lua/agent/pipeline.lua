-- ── Flujo de una acción ──────────────────────────────────────────────────────
-- objetivo → (entrada del usuario) → trabajo + ancla + spinner → contexto →
-- prompt → runner. Cada paso es de otro módulo; aquí solo se encadenan.
local actions = require "agent.actions"
local anchor = require "agent.anchor"
local context = require "agent.context"
local jobs = require "agent.jobs"
local log = require "utils.log"
local output = require "agent.output"
local prompt = require "agent.prompt"
local runner = require "agent.runner"
local selection = require "agent.selection"
local status = require "agent.ui.status"
local target_mod = require "agent.context.target"
local ui_prompt = require "agent.ui.prompt"

require("agent.ui.highlights").ensure()

local M = {}

---@param name string|table nombre de una acción, o la acción misma (las de agent/ddd viven en su propio registro)
---@param opts { range: integer[]? }?
function M.run(name, opts)
  opts = opts or {}
  local action = type(name) == "table" and name or actions.get(name)

  local sel = selection.current(action)
  if not sel then
    return log.error "Agent: no backend available (`claude`, `opencode`, a local Ollama…): run <leader>am → Setup"
  end
  if not sel.model and require("agent.backends").get(sel.backend).requires_model then
    return log.error(
      ("Agent: no model chosen for %s: run <leader>am → Setup (it detects, offers to pull one, and selects it)"):format(
        sel.backend
      )
    )
  end
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "" then
    return log.warn "Agent: only works in file buffers"
  end

  -- la selección visual se lee ANTES de abrir cualquier ventana
  local target, err = target_mod.resolve(buf, action.scope, opts.range or target_mod.visual_range())
  if not target then
    return log.warn("Agent: " .. err)
  end
  local problem = action.check and action.check(target)
  if problem then
    return log.warn("Agent: " .. problem)
  end
  -- `retarget`: el resultado va a OTRO sitio (p. ej. el archivo de pruebas); lo de aquí pasa a ser el `subject`,
  -- de donde sale el contexto, mientras el objetivo (lo que se reemplaza y se envía) es el destino
  local subject
  if action.retarget then
    local dest, why = action.retarget(target)
    if not dest then
      return log.warn("Agent: " .. why)
    end
    subject, target = target, dest
  end
  buf = target.buf
  if action.output == "replace" and jobs.overlaps(buf, target.first, target.last) then
    return log.warn "Agent: an agent is already working on that block"
  end

  ---@param input string?
  ---@param extra { name: string, text: string }[]? secciones que añadió `prepare`
  local function launch(input, extra)
    local job = jobs.create {
      action = action,
      target = target,
      subject = subject,
      buf = buf,
      selection = sel,
      presenter = output.get(action.output),
      anchor = anchor.create(buf, target.first, target.last),
      -- el spinner y el resumen se ven donde estás (el código bajo prueba), no en el archivo de destino
      view = subject and {
        buf = subject.buf,
        anchor = anchor.create(subject.buf, subject.first, subject.last),
        first = subject.first,
      } or nil,
    }
    status.attach(job) -- feedback inmediato, también mientras se reúne el contexto

    context.build(action, subject or target, function(sections)
      if job.state ~= "running" then
        return
      end
      if extra then
        sections = vim.list_extend(vim.list_slice(extra), sections)
      end
      job.input, job.sections = input, sections
      job.system, job.prompt = prompt.build(action, target, sections, input)
      runner.run(job)
    end)
  end

  local function start(input)
    if action.handler then
      return action.handler { target = target, input = input, selection = sel }
    end
    -- `prepare`: trabajo previo SIN modelo (correr las pruebas...). Si no hay nada que pedirle, se corta aquí: 0 tokens
    if action.prepare then
      log.info(("Agent %s: %s"):format(action.label, action.preparing or "preparing…"))
      return action.prepare(target, function(extra, why)
        if not extra then
          return log.info(("Agent %s: %s"):format(action.label, why or "nothing to do"))
        end
        launch(input, extra)
      end)
    end
    launch(input)
  end

  if action.input then
    ui_prompt.ask(action, target, selection.label(sel), function(text)
      start(text ~= "" and text or nil)
    end)
  else
    start(nil)
  end
end

return M
