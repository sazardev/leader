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
  if action.output == "replace" and jobs.overlaps(buf, target.first, target.last) then
    return log.warn "Agent: an agent is already working on that block"
  end

  local function start(input)
    if action.handler then
      return action.handler { target = target, input = input, selection = sel }
    end

    local job = jobs.create {
      action = action,
      target = target,
      buf = buf,
      selection = sel,
      presenter = output.get(action.output),
      anchor = anchor.create(buf, target.first, target.last),
    }
    status.attach(job) -- feedback inmediato, también mientras se reúne el contexto

    context.build(action, target, function(sections)
      if job.state ~= "running" then
        return
      end
      job.input, job.sections = input, sections
      job.system, job.prompt = prompt.build(action, target, sections, input)
      runner.run(job)
    end)
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
