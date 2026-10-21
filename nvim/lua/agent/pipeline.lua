-- ── Flow of an action ────────────────────────────────────────────────────────
-- target → (user input) → job + anchor + spinner → context →
-- prompt → guards → runner. Each step belongs to another module; here they are only chained.
--
-- Two entry points:
--   run(action)      what the menus call: it RESOLVES the target from the cursor, asks for the instruction, then launches
--   launch(spec)     what everything else calls (refine, retry, batches, plans): the target is already known
local actions = require "agent.actions"
local anchor = require "agent.anchor"
local backends = require "agent.backends"
local cache = require "agent.cache"
local context = require "agent.context"
local guards = require "agent.guards"
local jobs = require "agent.jobs"
local log = require "utils.log"
local output = require "agent.output"
local prompt = require "agent.prompt"
local runner = require "agent.runner"
local selection = require "agent.selection"
local status = require "agent.ui.status"
local target_mod = require "agent.context.target"
local trust = require "agent.trust"
local profiles = require "agent.profiles"
local sampling = require "agent.sampling"
local decompose = require "agent.decompose"
local selection_mod = require "agent.selection"
local ui_prompt = require "agent.ui.prompt"

require("agent.ui.highlights").ensure()
require("agent.features").setup() -- the optional features that hang off the agent's events (verification...)

local M = {}

---@class AgentLaunch
---@field action table
---@field target AgentTarget
---@field subject AgentTarget?           where the context comes from when the result goes elsewhere (retarget)
---@field selection AgentSelection
---@field input string?
---@field extra { name: string, text: string }[]?  sections added before the provider ones (prepare, previous proposal...)
---@field meta table?                    free data that travels with the job: { parent, attempt, batch, step... }
---@field preapproved boolean?           the user already confirmed this spend (a batch): the budget guard does not ask again

--- Starts a job on a target that is already known. Returns the job (it is running until it settles).
---@param spec AgentLaunch
---@return AgentJob
function M.launch(spec)
  local action, target, subject = spec.action, spec.target, spec.subject
  local buf = target.buf

  -- what this model can be trusted with (agent/profiles.lua). If it is not up to THIS request (the target is past its
  -- size, or the eval measured it failing this action) and the cascade is on, the main model takes it from the start
  local cap = require("core.settings").agent.capability
  local profile = cap.enabled and profiles.resolve(spec.selection, action.name, cap, profiles.load()) or nil
  local escalated, from
  if profile and (profile.declined or (profile.max_target_lines and #target.lines > profile.max_target_lines)) then
    local to = sampling.escalation(spec.selection)
    if to then
      from, escalated = selection_mod.label(spec.selection), true
      spec = vim.tbl_extend("force", spec, { selection = to })
      profile = profiles.resolve(to, action.name, cap, profiles.load())
      log.info(("Agent %s: %s is not up to this: using %s"):format(action.label, from, selection_mod.label(to)))
    end
  end

  local job = jobs.create {
    profile = profile,
    escalated = escalated,
    from = from,
    action = action,
    target = target,
    subject = subject,
    buf = buf,
    selection = spec.selection,
    meta = spec.meta or {},
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
  local backend = backends.get(spec.selection.backend)
  if backend.warm then
    backend.warm() -- a backend with a resident server boots it while the context is being gathered
  end

  context.build(action, subject or target, function(sections)
    if job.state ~= "running" then
      return
    end
    if spec.extra then
      sections = vim.list_extend(vim.list_slice(spec.extra), sections)
    end
    job.input, job.sections = spec.input, sections
    -- an instruction that is several things, for a profile that decomposes: a chain of single steps (agent/decompose.lua)
    job.steps = decompose.plan(action, spec.input, profile)
    if job.steps then
      job.step, job.working = 1, vim.deepcopy(target.lines)
    end
    job.system, job.prompt =
      prompt.build(action, target, sections, job.steps and decompose.step_input(spec.input, job.steps, 1) or spec.input)
    -- the same question about the same code was already answered: 0 tokens, no budget to check
    local cached = cache.lookup(job)
    if cached then
      status.clear(job)
      return runner.settle(job, cached)
    end
    local req = {
      action = action.name or action.label,
      backend = spec.selection.backend,
      model = spec.selection.model,
      tier = spec.selection.tier,
      sections = vim.tbl_map(function(s)
        return { name = s.name, chars = #s.text }
      end, sections),
      profile = profile and profile.name or nil,
      limits = profile and { max_target_lines = profile.max_target_lines, declined = profile.declined } or nil,
      target_lines = #target.lines,
      chars = #job.system + #job.prompt,
      count = job.steps and #job.steps or nil, -- the budget sees the whole chain, not its first step
      steps = job.steps and #job.steps or nil,
      system = job.system,
      prompt = job.prompt,
      preapproved = spec.preapproved,
    }
    guards.check(req, function()
      if job.state ~= "running" then -- it could have been cancelled while a question was open
        return
      end
      -- say what is about to happen: the estimate sits in the spinner, or as a full line, as the user prefers
      job.estimate = req.estimate or { tokens = require("agent.budget").tokens(req.chars) }
      job.preflight = trust.preflight(trust.from_request(req))
      if require("core.settings").agent.trust.preflight == "notify" then
        log.info(("Agent %s: %s"):format(action.label, job.preflight))
      end
      runner.run(job)
    end, function()
      runner.deny(job)
    end)
  end, { max_chars = profile and profile.context_chars or nil })
  return job
end

---@param name string|table name of an action, or the action itself (those of agent/ddd live in their own registry)
---@param opts { range: integer[]? }?
function M.run(name, opts)
  opts = opts or {}
  local action = type(name) == "table" and name or actions.get(name)

  local sel = selection.current(action)
  if not sel then
    return log.error "Agent: no backend available (`claude`, `opencode`, a local Ollama…): run <leader>am → Setup"
  end
  if not sel.model and backends.get(sel.backend).requires_model then
    return log.error(
      ("Agent: no model chosen for %s: run <leader>am → Setup (it detects, offers to pull one, and selects it)"):format(
        sel.backend
      )
    )
  end
  -- `standalone`: the action works on a whole project or a list, not on the code under the cursor (fix all, fix from
  -- output, multi-file plans, review of what is staged): it gets the selection and takes it from there
  if action.standalone then
    return action.handler { selection = sel, action = action }
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
  -- a generated file is rewritten on the next build: a change there would be lost (reading it is fine)
  if action.output == "replace" and require("utils.generated").is_generated(target.path) then
    return log.warn "Agent: this file is generated (build_runner, protobuf…): change its source and rebuild"
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
  local function go(input, extra)
    M.launch {
      action = action,
      target = target,
      subject = subject,
      selection = sel,
      input = input,
      extra = extra,
      meta = opts.meta,
    }
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
        go(input, extra)
      end)
    end
    go(input)
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
