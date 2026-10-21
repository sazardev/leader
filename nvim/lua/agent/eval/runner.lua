-- ── Running one case ─────────────────────────────────────────────────────────
-- The same road a keypress takes: a temp project from the case, the file opened, the cursor on its line, the target
-- resolved from it, `pipeline.launch`, the proposal accepted (or the findings read), then the judges. Nothing is
-- special-cased for the eval except what must not leak out of it: no spend guard question, no answer cache, no history
-- in the user's state, no formatter run, no LSP.
local backends = require "agent.backends"
local judge = require "agent.eval.judge"
local replay = require "agent.eval.replay"

local M = {}

---@class AgentEvalRun
---@field backend string
---@field model string?
---@field timeout_ms integer?
---@field sample integer?
---@field root string?       where the cassettes live (replay)
---@field record boolean?    save the answer as a cassette
---@field scaffold boolean?   false = no capability profile, no repairs, no cascade: the model on its own
---@field decompose boolean?  true/false forces the chain of single steps on/off for a multi-part instruction (nil = the profile decides)

--- Settings an eval must not inherit from the user: they are set for the run and put back
local OVERRIDES = {
  { "budget", "enabled", false }, -- a question nobody can answer in a batch run (the eval has its own cap)
  { "verify", "enabled", false }, -- waits for an LSP that is not there
  { "cache", "enabled", false }, -- a hit would hide the very call being measured
  { "apply", "format", false }, -- a formatter would change what the model wrote
}

---@param fn fun()
---@param run AgentEvalRun
local function with_overrides(fn, run)
  local agent = require("core.settings").agent
  local list = vim.deepcopy(OVERRIDES)
  if run.scaffold == false then -- the model bare: no profile, so no repairs, schema, chain or cascade
    list[#list + 1] = { "capability", "enabled", false }
    list[#list + 1] = { "cascade", "enabled", false }
  end
  local saved = {}
  for i, o in ipairs(list) do
    saved[i] = agent[o[1]][o[2]]
    agent[o[1]][o[2]] = o[3]
  end
  -- `decompose` forces the chain of steps on (or off) for every class: how it is measured on a model whose class would not
  local classes = { "small", "medium", "strong" }
  local chain = {} -- a list: a setting that was nil must be put back to nil, and a table cannot hold one
  if run.decompose ~= nil then
    for _, class in ipairs(classes) do
      chain[#chain + 1] = { class, agent.capability[class].decompose }
      agent.capability[class].decompose = run.decompose
    end
  end
  local ok, err = pcall(fn)
  for i, o in ipairs(list) do
    agent[o[1]][o[2]] = saved[i]
  end
  for _, saved_chain in ipairs(chain) do
    agent.capability[saved_chain[1]].decompose = saved_chain[2]
  end
  if not ok then
    error(err, 0)
  end
end

--- A temp project holding the case's files, in a git repo (the history provider reads it), made the cwd
---@param case AgentEvalCase
---@return string dir
local function materialize(case)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  for _, path in ipairs(vim.fn.glob(case.dir .. "/**/*", false, true)) do
    local rel = path:sub(#case.dir + 2)
    if vim.fn.isdirectory(path) == 0 and rel ~= "case.json" then
      vim.fn.mkdir(vim.fs.dirname(dir .. "/" .. rel), "p")
      vim.fn.writefile(vim.fn.readfile(path, "b"), dir .. "/" .. rel, "b")
    end
  end
  local git = { "git", "-C", dir, "-c", "user.email=eval@eval", "-c", "user.name=eval", "-c", "commit.gpgsign=false" }
  vim.fn.system { "git", "-C", dir, "init", "-q" }
  vim.fn.system(vim.list_extend(vim.deepcopy(git), { "add", "-A" }))
  vim.fn.system(vim.list_extend(vim.deepcopy(git), { "commit", "-qm", "base" }))
  vim.cmd.cd(dir)
  return dir
end

---@param spec table
---@param buf integer
local function seed_diagnostics(spec, buf)
  local list = {}
  for _, d in ipairs(spec.diagnostics or {}) do
    list[#list + 1] = {
      lnum = d.line - 1,
      col = 0,
      end_lnum = d.line - 1,
      end_col = 1,
      severity = d.severity == "warn" and vim.diagnostic.severity.WARN or vim.diagnostic.severity.ERROR,
      message = d.message,
      source = d.source or "lsp",
    }
  end
  vim.diagnostic.set(vim.api.nvim_create_namespace "agent.eval.seed", buf, list)
end

--- Nothing the eval does may touch the user's real state files
local function isolate()
  require("agent.runs.store").use(vim.fn.tempname() .. ".jsonl")
  require("agent.cache").use(vim.fn.tempname() .. ".json")
  require("agent.persist").use(vim.fn.tempname() .. ".json")
  vim.lsp.start = function()
    return nil
  end
end

---@param case AgentEvalCase
---@param run AgentEvalRun
---@return table result
function M.run(case, run)
  local result = {
    case = case.id,
    action = case.action,
    model = run.backend == "replay" and ("replay:" .. run.model)
      or ((run.backend or "?") .. "/" .. (run.model or "default")),
    sample = run.sample or 1,
    status = "ok",
    parsed = false,
    applied = false,
    answers = {},
    pass = false,
  }
  local function fail(status, why)
    result.status, result.error = status, why
    return result
  end

  local problems = require("agent.eval.cases").problems(case)
  if #problems > 0 then
    return fail("error", "bad case: " .. table.concat(problems, "; "))
  end
  if not backends.is_available(run.backend) then
    return fail("error", "backend not available: " .. tostring(run.backend))
  end
  local action = require("agent.actions").get(case.action)
  if action.output ~= "replace" and action.output ~= "findings" then
    return fail("error", "the eval judges replace and findings actions, not " .. tostring(action.output))
  end
  if action.retarget or action.prepare or action.standalone or action.handler then
    return fail("error", "the eval does not drive actions that retarget, prepare or run their own handler")
  end

  isolate()
  local spec = case.spec
  local dir = materialize(case)
  vim.cmd("silent edit " .. dir .. "/" .. spec.file)
  vim.bo.filetype = spec.lang
  local buf = vim.api.nvim_get_current_buf()
  pcall(vim.api.nvim_win_set_cursor, 0, { spec.line, 0 })
  seed_diagnostics(spec, buf)

  local target, err = require("agent.context.target").resolve(buf, action.scope, nil)
  if not target then
    return fail("error", "no target: " .. tostring(err))
  end
  local problem = action.check and action.check(target)
  if problem then
    return fail("error", "action does not apply: " .. problem)
  end

  local before = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  replay.current = { case = case, model = run.model, target_lines = target.lines, root = run.root }

  local job
  with_overrides(function()
    job = require("agent.pipeline").launch {
      action = action,
      target = target,
      selection = { backend = run.backend, model = run.model, tier = "main" },
      input = spec.input,
      meta = { eval = true },
    }
    vim.wait(run.timeout_ms or 180000, function()
      return job.state ~= "running"
    end, 20)
  end, run)
  result.attempts, result.escalated = job.spent and job.spent.calls or 1, job.escalated or false
  result.profile = job.profile and job.profile.name or nil

  if job.state == "running" then
    require("agent.runner").cancel(job)
    return fail("error", "timed out")
  end
  if job.state ~= "done" then
    local rec = require("agent.runs.store").read()
    local last = rec[#rec]
    return fail("error", (last and last.error) or job.state)
  end

  local usage = job.result and job.result.usage or {}
  result.tokens_in, result.tokens_out, result.cost = usage.tokens_in, usage.tokens_out, usage.cost
  result.ms = math.floor(require("agent.jobs").elapsed(job) * 1000)
  result.response = job.result and job.result.text

  if run.record and run.backend ~= "replay" then
    replay.save(run.root or require("agent.eval.cases").root(), case.id, result.model, {
      text = job.result.text,
      usage = usage,
    })
  end

  local protocol = require "agent.protocol"
  local findings
  if action.output == "findings" then
    local items = protocol.parse_findings(job.result.text)
    result.parsed = #items > 0 or protocol.is_ok(job.result.text)
    result.applied = #items > 0
    findings = vim.tbl_map(function(d)
      return { line = d.lnum + 1 }
    end, vim.diagnostic.get(buf, { namespace = require("agent.output.findings").namespace() }))
  else
    local code = protocol.extract_code(job.result.text, target.lines)
    result.parsed = code ~= nil
    if job.proposal then
      result.applied = require("agent.output.replace").accept_proposal(job.proposal, { keep_cursor = true })
    end
  end

  local after = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  result.answers = judge.judge(spec.check, {
    before = before,
    after = after,
    first = target.first,
    last = target.last,
    findings = findings,
  })
  if not result.parsed then
    result.answers.parsed = false
  end

  local cmd = spec.check.cmd
  if cmd then
    vim.cmd "silent write"
    local out = vim.system(cmd, { cwd = dir, text = true, timeout = 60000 }):wait()
    result.answers.cmd = out.code == 0
    if out.code ~= 0 then
      result.cmd_output = require("agent.text").clip((out.stdout or "") .. (out.stderr or ""), 600)
    end
  end

  result.pass = judge.passes(result.answers)
  result.failed = judge.failed(result.answers)
  vim.cmd "silent! bwipeout!"
  vim.fn.delete(dir, "rf")
  return result
end

return M
