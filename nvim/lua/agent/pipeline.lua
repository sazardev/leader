-- ── Flow of an action ────────────────────────────────────────────────────────
-- target → (user input) → job + anchor + spinner → context →
-- prompt → runner. Each step belongs to another module; here they are only chained.
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

---@param name string|table name of an action, or the action itself (those of agent/ddd live in their own registry)
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

  -- the visual selection is read BEFORE opening any window
  local target, err = target_mod.resolve(buf, action.scope, opts.range or target_mod.visual_range())
  if not target then
    return log.warn("Agent: " .. err)
  end
  local problem = action.check and action.check(target)
  if problem then
    return log.warn("Agent: " .. problem)
  end
  -- `retarget`: the result goes ELSEWHERE (e.g. the test file); what is here becomes the `subject`,
  -- where the context comes from, while the target (what is replaced and sent) is the destination
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
  ---@param extra { name: string, text: string }[]? sections added by `prepare`
  local function launch(input, extra)
    local job = jobs.create {
      action = action,
      target = target,
      subject = subject,
      buf = buf,
      selection = sel,
      presenter = output.get(action.output),
      anchor = anchor.create(buf, target.first, target.last),
      -- the spinner and the summary show where you are (the code under test), not in the destination file
      view = subject and {
        buf = subject.buf,
        anchor = anchor.create(subject.buf, subject.first, subject.last),
        first = subject.first,
      } or nil,
    }
    status.attach(job) -- immediate feedback, also while the context is being gathered

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
    -- `prepare`: prior work WITHOUT a model (running the tests...). If there is nothing to ask it, it stops here: 0 tokens
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
