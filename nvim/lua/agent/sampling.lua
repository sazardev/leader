-- ── A second try, and a stronger model as the last resort ────────────────────
-- What a profile (agent/profiles.lua) does when the model's answer cannot be used. Free checks first (the protocol's own
-- parser, and whether the new code still parses); if the answer fails one, the SAME job asks again with the reason in the
-- prompt (what it said and what was wrong with it), up to `profile.repairs` times; and when those are spent, with
-- `settings.agent.cascade` on, it goes to the main model instead of showing a broken answer. Each step is one call the
-- history records as part of the job: the usage of every attempt is added up, so the bill is the real one.
local protocol = require "agent.protocol"
local syntax = require "agent.syntax"
local text = require "agent.text"

local M = {}

--- Why an answer cannot be used, or nil when it can (as far as a free check can tell)
---@param job AgentJob
---@param result table backend result: { text }
---@return string?
function M.problem(job, result)
  local action = job.action
  if action.output == "findings" then
    if protocol.is_ok(result.text) or #protocol.parse_findings(result.text) > 0 then
      return nil
    end
    return "it has no finding in the required format `L<line>|<error|warn|info>|<message>`, and is not just `OK`"
  end
  if action.output ~= "replace" then
    return nil
  end
  local code, _, err = protocol.extract_code(result.text, job.target.lines)
  if not code then
    return err
  end
  if action.merge then
    local ok, merged = pcall(action.merge, vim.deepcopy(code), job.target)
    if not ok or not merged then
      return "it could not be joined to the code it belongs to"
    end
    code = merged
  end
  local buf = job.target.buf
  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end
  local found = syntax.after_replace(
    vim.api.nvim_buf_get_lines(buf, 0, -1, false),
    job.target.first,
    job.target.last,
    code,
    vim.bo[buf].filetype
  )
  if found and found.added > 0 then
    return ("the code does not parse (a syntax error near line %d of the file)"):format(found.row or job.target.first)
  end
  return nil
end

--- The prompt of the second try: the original, then what went wrong with the answer
---@param job AgentJob
---@param result table
---@param problem string
---@return string
function M.amend(job, result, problem)
  return table.concat({
    job.base_prompt or job.prompt,
    "",
    "<previous-answer>",
    text.clip(result.text, 1200),
    "</previous-answer>",
    ("Your previous answer could not be used: %s."):format(problem),
    "Answer again from the task above. Follow the OUTPUT rules exactly, and fix that problem.",
  }, "\n")
end

--- Adds an attempt's usage to the job's running total
---@param job AgentJob
---@param usage table?
function M.charge(job, usage)
  usage = usage or {}
  local t = job.spent or { tokens_in = 0, tokens_out = 0, cost = 0, calls = 0 }
  job.spent = {
    tokens_in = t.tokens_in + (usage.tokens_in or 0),
    tokens_out = t.tokens_out + (usage.tokens_out or 0),
    cost = t.cost + (usage.cost or 0),
    calls = t.calls + 1,
  }
end

--- The result's usage replaced by the total of every call the job made (repairs, steps, an escalation), when there was more than one
---@param job AgentJob
---@param result table
function M.settle_usage(job, result)
  local spent = job.spent
  if spent and spent.calls > 1 then
    result.usage = vim.tbl_extend("force", result.usage or {}, {
      tokens_in = spent.tokens_in,
      tokens_out = spent.tokens_out,
      cost = spent.cost,
      attempts = spent.calls,
    })
  end
end

--- Who to ask when this model is not enough: the main model, if it is another one (or `settings.agent.cascade.to`)
---@param sel AgentSelection
---@return AgentSelection?
function M.escalation(sel)
  local cfg = require("core.settings").agent.cascade
  if not cfg.enabled then
    return nil
  end
  local backends = require "agent.backends"
  if cfg.to then
    local backend, model = cfg.to:match "^([^/]+)/(.+)$"
    backend = backend or cfg.to
    if backends.is_available(backend) and (backend ~= sel.backend or model ~= sel.model) then
      return { backend = backend, model = model, tier = "main" }
    end
    return nil
  end
  local main = require("agent.selection").current(nil)
  if main and (main.backend ~= sel.backend or main.model ~= sel.model) then
    return main
  end
  return nil
end

--- Moves the job to the stronger model, if there is one; says so
---@param job AgentJob
---@param why string
---@return boolean moved
function M.escalate(job, why)
  if job.escalated then
    return false
  end
  local to = M.escalation(job.selection)
  if not to then
    return false
  end
  local selection = require "agent.selection"
  require("utils.log").info(
    ("Agent %s: %s failed (%s): trying %s"):format(
      job.action.label,
      selection.label(job.selection),
      text.clip(why, 80),
      selection.label(to)
    )
  )
  job.escalated, job.from = true, selection.label(job.selection)
  job.selection = to
  job.attempt = 1
  job.profile = require("agent.profiles").resolve(
    to,
    job.action.name,
    require("core.settings").agent.capability,
    require("agent.profiles").load()
  )
  job.prompt = job.base_prompt or job.prompt
  return true
end

--- Decides what happens with an answer that has a problem: "retry" (the job asks again) or nil (show what there is)
---@param job AgentJob
---@param result table
---@param problem string
---@return "retry"?
function M.advance(job, result, problem)
  job.base_prompt = job.base_prompt or job.prompt
  local attempt = job.attempt or 1
  local repairs = job.profile and job.profile.repairs or 0
  if attempt <= repairs then
    job.attempt = attempt + 1
    job.prompt = M.amend(job, result, problem)
    return "retry"
  end
  if M.escalate(job, problem) then
    return "retry"
  end
  return nil
end

return M
