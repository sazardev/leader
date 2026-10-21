-- ── Build with agent: the run's state ────────────────────────────────────────
-- Everything a build knows, apart from any window: the phase, the models of each phase, the plan, every file with what
-- went in and came out (tokens, cache, cost, time), the checks, the feed and the totals. The view draws it, the statusline
-- reads it, and it is saved after every step (state dir, per project) so a build interrupted by closing Neovim resumes.
local M = {}

M.PHASES = { "ready", "plan", "review", "write", "check", "fix", "use", "done" }

---@class BuildFileState: BuildFile
---@field state "pending"|"writing"|"done"|"failed"|"fixed"|"skipped"
---@field lines integer?
---@field tokens_in integer?
---@field tokens_out integer?
---@field cached integer?
---@field cost number?
---@field ms integer?
---@field model string?
---@field sent integer?     characters sent
---@field api integer?      characters of the API index it carried
---@field estimate integer? input tokens estimated before it ran
---@field existed boolean?  a project file a layer build changes (scope.lua), not one it created

---@class BuildFeed
---@field kind "step"|"in"|"out"|"info"|"fail"
---@field title string?
---@field text string
---@field meta string?

---@class BuildRun
---@field root string
---@field name string
---@field scope string?          what this build covers (scope.lua; nil = the whole project)
---@field existing string[]?     the project's files a layer build built on (read again from disk on a resume)
---@field task BuildTask?        the requirement or recipe of a task build (feature, recipe)
---@field phase string           one of PHASES, or "stopped"/"failed" (where it ended)
---@field outcome string?        the last line: "✓ built · …", "✗ …"
---@field tiers { plan: string, files: string, fixes: string, use: string }   "main"|"light" per phase
---@field max_fixes integer
---@field docs { file: string, chars: integer }[]
---@field plan BuildPlan?
---@field files BuildFileState[]
---@field checks { label: string, state: string }[]
---@field fix_round integer
---@field looked boolean?        the rendered screens were compared with DESIGN.md (no more looks this build)
---@field looks integer?         looks so far (`look_rounds` at most)
---@field use { fixes: integer, plays: integer?, scenarios: UseScenario[]?, kind: string?, passed: integer?, total: integer?, issues: integer?, dir: string?, done: boolean?, error: string? }?
---@field feed BuildFeed[]
---@field totals { requests: integer, tokens_in: integer, tokens_out: integer, cached: integer, cost: number }
---@field estimate { tokens: integer, cost: number? }?
---@field current string?        the file being written or fixed
---@field started integer        os.time()
---@field elapsed integer        seconds spent running (survives a resume)
---@field running boolean
---@field replaced integer?      files that will be replaced
---@field stale string[]?        files of the previous build this plan drops
---@field loss { lines: integer, types: integer, significant: boolean, text: string[] }?  what dropping them loses (loss.lua)
---@field proven_before string[]? requirements a test named before this build started
---@field proof BuildProof?      what the finished build can claim (proof.lua)
---@field at string?             the last phase it was in (a stopped run shows where it stopped)

---@type BuildRun?
M.run = nil

local listeners = {} ---@type fun()[]

---@param fn fun()
function M.subscribe(fn)
  listeners[#listeners + 1] = fn
end

--- Something changed: the view and the statusline redraw
function M.changed()
  local run = M.run
  if run and run.phase ~= "ready" and run.phase ~= "stopped" and run.phase ~= "failed" then
    run.at = run.phase -- where a stopped or failed run was (the view's phases show it)
  end
  for _, fn in ipairs(listeners) do
    pcall(fn)
  end
end

---@param root string
---@param docs { file: string, chars: integer }[]
---@param scope string? "all" (default) or a layer (scope.lua)
---@param task BuildTask? what a task scope builds
---@return BuildRun
function M.new(root, docs, scope, task)
  local settings = (require("core.settings").agent.kit or {}).build or {}
  M.run = {
    root = root,
    name = vim.fs.basename(root),
    scope = scope and scope ~= "all" and scope or nil,
    task = task,
    phase = "ready",
    tiers = {
      plan = settings.plan or "main",
      files = settings.files or "main",
      fixes = settings.fixes or "main",
      use = settings.use_tier or "main",
    },
    max_fixes = settings.max_fixes or 2,
    docs = docs,
    files = {},
    checks = {},
    fix_round = 0,
    feed = {},
    totals = { requests = 0, tokens_in = 0, tokens_out = 0, cached = 0, cost = 0 },
    started = os.time(),
    elapsed = 0,
    running = false,
  }
  return M.run
end

---@param kind "step"|"in"|"out"|"info"|"fail"
---@param text string
---@param meta string?
---@param title string?
function M.feed(kind, text, meta, title)
  if not M.run then
    return
  end
  M.run.feed[#M.run.feed + 1] = { kind = kind, text = text, meta = meta, title = title }
  M.changed()
end

---@param usage table?
function M.add_usage(usage)
  local t = M.run and M.run.totals
  if not t or not usage then
    return
  end
  t.requests = t.requests + 1
  t.tokens_in = t.tokens_in + (usage.tokens_in or 0)
  t.tokens_out = t.tokens_out + (usage.tokens_out or 0)
  t.cached = t.cached + (usage.cache_read or 0)
  t.cost = t.cost + (usage.cost or 0)
end

---@param path string
---@return BuildFileState?
function M.file(path)
  for _, f in ipairs(M.run and M.run.files or {}) do
    if f.path == path then
      return f
    end
  end
end

--- How many files are done (written, fixed) and how many count (not skipped)
---@return integer done, integer total
function M.progress()
  local done, total = 0, 0
  for _, f in ipairs(M.run and M.run.files or {}) do
    if f.state ~= "skipped" then
      total = total + 1
      if f.state == "done" or f.state == "fixed" then
        done = done + 1
      end
    end
  end
  return done, total
end

-- ── Saved per project ────────────────────────────────────────────────────────

--- Where a project's run is saved: one per scope, so a domain build and the whole build never overwrite each other
---@param root string
---@param scope string? nil/"all" = the whole build (the name it always had)
---@return string
function M.path(root, scope)
  local suffix = scope and scope ~= "all" and ("." .. scope) or ""
  return vim.fn.stdpath "state" .. "/agent-build/" .. vim.fn.sha256(root):sub(1, 16) .. suffix .. ".run.json"
end

--- Saves the run (the feed is kept short: the history has every prompt and answer)
function M.save()
  local run = M.run
  if not run then
    return
  end
  local copy = vim.deepcopy(run)
  copy.running = false
  copy.feed = vim.list_slice(copy.feed, math.max(1, #copy.feed - 200))
  local path = M.path(run.root, run.scope)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local ok, json = pcall(vim.json.encode, copy)
  if ok then
    local f = io.open(path, "w")
    if f then
      f:write(json)
      f:close()
    end
  end
end

--- The saved run of a project, if any
---@param root string
---@param scope string?
---@return BuildRun?
function M.load(root, scope)
  local f = io.open(M.path(root, scope), "r")
  if not f then
    return nil
  end
  local text = f:read "*a"
  f:close()
  local ok, run = pcall(vim.json.decode, text, { luanil = { object = true, array = true } })
  if
    ok
    and type(run) == "table"
    and run.root == root
    and type(run.files) == "table"
    and (run.scope or "all") == (scope or "all")
  then
    run.running = false
    return run
  end
end

--- Can this saved run go on? (it has a plan and files not written yet, and it did not end well)
---@param run BuildRun?
---@return boolean
function M.resumable(run)
  if not run or not run.plan or run.phase == "done" then
    return false
  end
  for _, f in ipairs(run.files) do
    if f.state == "pending" or f.state == "writing" or f.state == "failed" then
      return true
    end
  end
  return run.phase == "check" or run.phase == "fix" or run.phase == "stopped" or run.phase == "failed"
end

-- ── Statusline ───────────────────────────────────────────────────────────────

local SPIN = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

--- "⠹ build 7/25 · $0.031" while it runs; "" otherwise
---@return string
function M.statusline()
  local run = M.run
  if not run or not run.running then
    return ""
  end
  local spin = SPIN[math.floor(vim.uv.hrtime() / 1e8) % #SPIN + 1]
  local done, total = M.progress()
  -- "build FR-8", "build screen-riverpod:Profile", "build domain"
  local build = run.task and ("build " .. run.task.id:gsub("^.*/", ""))
    or run.scope and ("build " .. run.scope)
    or "build"
  local what = (run.phase == "write" and ("%s %d/%d"):format(build, done, total))
    or (run.phase == "plan" and (build .. " planning"))
    or (run.phase == "check" and (build .. " checking"))
    or (run.phase == "fix" and ("%s fixing %d"):format(build, run.fix_round))
    or (run.phase == "use" and (build .. " using the app"))
    or (build .. " " .. run.phase)
  return (" %s %s · $%.3f "):format(spin, what, run.totals.cost)
end

return M
