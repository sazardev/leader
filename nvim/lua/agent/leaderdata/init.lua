-- ── .leader/: how Leader worked on this project, kept on this machine ────────
-- A build that ends and the agent's actions leave events in `<project>/.leader/events.jsonl` (store.lua), each one passed through
-- the schema (schema.lua) that lets through counts, sizes, durations, costs, models and outcomes and nothing else: no code, no
-- prompts, no file names (hashes), no document or error text. For measuring Leader, never for reading the person's work.
-- Offline always: no module here opens a network connection. The builder creates the folder; the inline agent writes to it only
-- when it already exists (a project that never built with Leader is not given one by a keypress).
local redact = require "agent.leaderdata.redact"
local schema = require "agent.leaderdata.schema"
local store = require "agent.leaderdata.store"

local M = {}

--- Writes one event of `kind` (sanitized by its schema). Never raises: recording must not break the work
---@param root string
---@param kind string
---@param fields table
---@return boolean
function M.record(root, kind, fields)
  if not store.enabled() then
    return false
  end
  local ok, wrote = pcall(function()
    local event = schema.sanitize(kind, fields)
    if not event then
      return false
    end
    event.kind, event.ts, event.v = kind, os.time(), 1
    return store.append(root, event)
  end)
  return ok and wrote or false
end

---@param run BuildRun
---@return "done"|"partial"|"failed"|"stopped"
local function outcome_of(run)
  if run.phase == "done" then
    local o = run.outcome or ""
    return (o:find "^◐" or o:find "^⚠") and "partial" or "done"
  elseif run.phase == "stopped" then
    return "stopped"
  end
  return "failed"
end

--- The fields of a finished (or failed, or stopped) build: counts, costs, outcomes, a hash per file
---@param run BuildRun
---@param salt string
---@return table
function M.build_fields(run, salt)
  local totals = run.totals or {}
  local plan = run.plan or {}
  local proof = run.proof or {}
  local use = run.use or {}
  local files = {}
  local done, failed = 0, 0
  for _, f in ipairs(run.files or {}) do
    if f.state == "done" or f.state == "fixed" then
      done = done + 1
    elseif f.state == "failed" then
      failed = failed + 1
    end
    files[#files + 1] = {
      id = redact.hash(salt, f.path),
      ext = redact.ext(f.path),
      lines = redact.bucket(f.lines),
      tokens_in = f.tokens_in,
      tokens_out = f.tokens_out,
      cost = f.cost,
      ms = f.ms,
      model = f.model,
      state = f.state,
    }
  end
  local checks = {}
  for _, c in ipairs(run.checks or {}) do
    checks[#checks + 1] = { label = c.label, ok = c.state == "done" }
  end
  local scope = run.scope or "all"
  if run.task then
    scope = run.task.kind == "recipe" and "recipe" or "feature"
  end
  local tiers = run.tiers or {}
  return {
    build = redact.hash(salt, tostring(run.started)),
    scope = scope,
    outcome = outcome_of(run),
    strict = (require("core.settings").agent.kit.build or {}).strict == true,
    files = #(run.files or {}),
    files_done = done,
    files_failed = failed,
    fix_rounds = run.fix_round,
    seconds = run.elapsed,
    requests = totals.requests,
    tokens_in = totals.tokens_in,
    tokens_out = totals.tokens_out,
    tokens_cached = totals.cached,
    cost = totals.cost,
    tier_plan = tiers.plan,
    tier_files = tiers.files,
    tier_fixes = tiers.fixes,
    tier_use = tiers.use,
    risks = #(plan.risks or {}),
    deferred = #(plan.deferred or {}),
    warnings = #(plan.warnings or {}),
    problems = #(plan.problems or {}),
    existing = #(run.existing or {}),
    replaced = run.replaced,
    stale = #(run.stale or {}),
    loss_lines = run.loss and run.loss.lines,
    loss_types = run.loss and run.loss.types,
    req_total = proof.total,
    req_proven = proof.proven,
    req_core_unproven = proof.core_unproven and #proof.core_unproven,
    placeholders = proof.placeholders and #proof.placeholders,
    regressions = proof.regressions and #proof.regressions,
    removed_api = proof.lost and #proof.lost,
    use_total = use.total,
    use_passed = use.passed,
    use_issues = use.issues,
    checks = checks,
    per_file = files,
  }
end

--- A build settled (done, failed or stopped): the builder calls this from its `finish`
---@param run BuildRun
function M.build_finished(run)
  if not store.enabled() then
    return
  end
  pcall(function()
    local _, salt = store.ensure(run.root)
    if salt then
      M.record(run.root, "build.finish", M.build_fields(run, salt))
    end
  end)
end

-- ── the inline agent: only where the folder already exists ───────────────────

---@return string?
local function project_root()
  local ok, root = pcall(function()
    return require("agent.kit.snapshot").root()
  end)
  return ok and root or nil
end

---@param job AgentJob
---@return string
local function run_id(job)
  local _, salt = store.ensure(project_root() or vim.fn.getcwd())
  return redact.hash(salt or "", tostring(job.record_id or job.id))
end

local subscribed = false

--- Subscribes to the agent's events (agent/features.lua calls it)
function M.setup()
  if subscribed then
    return
  end
  subscribed = true
  local events = require "agent.events"
  events.on("job.settled", function(ev)
    local root = project_root()
    if not (root and store.enabled() and store.exists(root)) then
      return
    end
    local job = ev.job
    local usage = (job.result and job.result.usage) or {}
    local spent = job.spent or {}
    M.record(root, "agent.run", {
      run = run_id(job),
      action = job.action.name,
      backend = job.selection.backend,
      model = job.selection.model,
      tier = job.selection.tier,
      profile = job.profile and job.profile.name,
      outcome = ev.outcome,
      lang = redact.lang(job.target and job.target.lang),
      target_lines = redact.bucket(job.target and #job.target.lines),
      tokens_in = spent.tokens_in or usage.tokens_in,
      tokens_out = spent.tokens_out or usage.tokens_out,
      cost = spent.cost or usage.cost,
      ms = math.floor(require("agent.jobs").elapsed(job) * 1000),
      calls = spent.calls or 1,
      steps = job.steps and #job.steps or nil,
      escalated = job.escalated or false,
      cached = usage.cached or false,
    })
  end)
  local function decision(job, what)
    local root = project_root()
    if root and store.enabled() and store.exists(root) then
      M.record(root, "agent.decision", { run = run_id(job), action = job.action.name, decision = what })
    end
  end
  events.on("proposal.accepted", function(ev)
    decision(ev.job, "accepted")
  end)
  events.on("proposal.dropped", function(ev)
    decision(ev.job, ev.how)
  end)
end

--- Opens the report of this project in a scratch buffer (`<leader>aSl`)
function M.open()
  local root = project_root()
  if not root then
    return require("utils.log").info "Leader data: no project here"
  end
  local lines = require("agent.leaderdata.report").render(store.read(root), vim.fs.basename(root))
  vim.cmd "enew"
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = "nofile", "wipe", false
  vim.bo[buf].filetype, vim.bo[buf].modifiable = "markdown", false
  vim.api.nvim_buf_set_name(buf, "leader-data://" .. vim.fs.basename(root))
end

return M
