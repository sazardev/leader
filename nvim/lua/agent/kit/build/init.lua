-- ── Build with agent (<leader>aSb…) ──────────────────────────────────────────
-- The project from its four documents (AGENTS.md, STACK.md, DESIGN.md, SPEC.md: it says which is missing and its key), or
-- one layer of it from the document that describes it (scope.lua: foundation from STACK.md, domain from SPEC.md, design
-- from DESIGN.md, each on top of the files the project already has), in phases you can watch and steer from the build
-- tab (build/view.lua):
--   ready   pre-flight: the documents, the model of each phase (plan · files · fixes, main or light tier), fix rounds
--   plan    one request: the ordered files, their documents and the earlier files they use (plan.lua)
--   review  the plan with what each file will cost; skip files, change models; Enter starts (this IS the confirmation)
--   write   one small request per file (prompt.lua: documents + plan in the cached system prompt, the API of what exists)
--   check   the manifest's own tools (verify.lua), never commands from the model; gofmt fixes itself; then what the plan
--           exports must be used by another file (wiring.lua: a feature only its tests reach is not finished)
--   fix     the files the errors name, with their errors, `max_fixes` rounds; then check again
--   use     the app used like its user would (use/: scenarios from SPEC.md, a driver per kind of app, free checks per
--           step, one verdict request); what fails is fixed, the same scenarios replayed (`use_rounds`)
--   look    the rendered screens against DESIGN.md (Go teatest golden files), `look_rounds` times at most
-- The run lives in build/state.lua, not in the window: closing the tab (q) leaves it running, the statusline shows it,
-- its key (<leader>aSbb, or the layer's) brings the view back, `x` stops it. It is saved after every step: a build cut short (Neovim closed) resumes.
-- Every request goes through the spend guard (no question per file once the review is accepted; the caps still apply)
-- and lands in the history (<leader>ah: kit_build_plan, kit_build_file, kit_build_fix, kit_build_scenarios, kit_build_use).
-- An answer that is not a clean file (a fence with prose, echoed tags, tool-call markup) is cleaned (clean.lua) and, when
-- that is not enough, asked again once before anything is written.
local clean = require "agent.kit.build.clean"
local compose = require "agent.kit.compose"
local diagnose = require "agent.kit.build.diagnose"
local edits = require "agent.kit.build.edits"
local look_mod = require "agent.kit.build.look"
local log = require "utils.log"
local plan_mod = require "agent.kit.build.plan"
local prompt = require "agent.kit.build.prompt"
local scopes = require "agent.kit.build.scope"
local state = require "agent.kit.build.state"
local verify = require "agent.kit.build.verify"
local wiring = require "agent.kit.build.wiring"

local M = {}

local KEYS = { ["AGENTS.md"] = "a", ["STACK.md"] = "t", ["DESIGN.md"] = "d", ["SPEC.md"] = "s" }

M.MAX_ROUNDS = 8

--- What a failure is, to tell a round that made progress from one that did not: the failing check and its failing
--- tests (or its first error lines), without timings or paths that change from run to run (pure)
---@param label string
---@param output string
---@return string
function M.signature(label, output)
  local names = {}
  for name in ("\n" .. output):gmatch "\n%s*%-%-%- FAIL: (%S+)" do
    names[#names + 1] = name
  end
  if #names == 0 then
    for line in output:gmatch "[^\n]+" do
      -- `file.go:12:`, TypeScript's `file.ts(12,5)`, a scenario or wiring finding
      if line:find ":%d+" or line:find "%(%d+,%d+%)" or line:find "^✗ " then
        names[#names + 1] = (line:gsub("%(%d+%.%d+s%)", ""):gsub("%d+%.%d+s", ""))
        if #names >= 3 then
          break
        end
      end
    end
  end
  table.sort(names)
  return label .. "|" .. table.concat(names, ";")
end

--- What is running now: the request's process (to stop it) and when this stretch of running began
local live = { handle = nil, since = nil, docs = nil, written = nil, prompts = {}, autofixed = {}, review_at = nil }

local record -- forward (below: ADR and PROGRESS.md)

---@return BuildRun
local function run()
  return state.run --[[@as BuildRun]]
end

---@return table
local function view()
  return require "agent.kit.build.view"
end

-- ── Documents, manifest, estimates ───────────────────────────────────────────

--- The documents a build reads, at the root: their text by id, and the files it needs that are missing (the whole
--- build needs all four; a layer only its own, scope.lua, and reads the others it uses when they are there)
---@param root string
---@param scope string?
---@return table<string, string>, string[]
function M.docs(root, scope)
  local s = scopes.get(scope)
  local docs, missing = {}, {}
  for _, d in ipairs(compose.DOCS) do
    if vim.tbl_contains(s.docs, d.id) then
      local text = require("utils.project").read(root .. "/" .. d.file)
      if text and vim.trim(text) ~= "" then
        docs[d.id] = text
      elseif vim.tbl_contains(s.required, d.id) then
        missing[#missing + 1] = d.file
      end
    end
  end
  return docs, missing
end

---@param docs table<string, string>
---@param scope string?
---@return { file: string, chars: integer }[]
function M.doc_sizes(docs, scope)
  local s = scopes.get(scope)
  local out = {}
  for _, d in ipairs(compose.DOCS) do
    if vim.tbl_contains(s.required, d.id) or docs[d.id] then
      out[#out + 1] = { file = d.file, chars = #(docs[d.id] or "") }
    end
  end
  return out
end

--- Where the list of files the last build of `root` wrote is kept (state dir, not the repository), one per scope: a
--- domain build's replan only drops the domain's own old files
---@param root string
---@param scope string?
---@return string
function M.manifest_path(root, scope)
  local suffix = scope and scope ~= "all" and ("." .. scope) or ""
  return vim.fn.stdpath "state" .. "/agent-build/" .. vim.fn.sha256(root):sub(1, 16) .. suffix .. ".json"
end

---@param root string
---@param scope string?
---@return string[]
function M.previous(root, scope)
  local text = require("utils.project").read(M.manifest_path(root, scope))
  local ok, list = pcall(vim.json.decode, text or "")
  return ok and type(list) == "table" and list or {}
end

---@param root string
---@param scope string?
---@param paths string[]
local function remember(root, scope, paths)
  if scopes.get(scope).additive then -- a feature or a recipe adds to the project: nothing of it is ever stale
    return
  end
  local path = M.manifest_path(root, scope)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = io.open(path, "w")
  if f then
    f:write(vim.json.encode(paths))
    f:close()
  end
end

--- Files the previous build wrote that this plan drops and are still there (same package, old names: they would clash)
---@param root string
---@param previous string[]
---@param plan BuildPlan
---@return string[]
function M.stale(root, previous, plan)
  local planned = {}
  for _, f in ipairs(plan.files) do
    planned[f.path] = true
  end
  return vim.tbl_filter(function(p)
    return not planned[p] and vim.uv.fs_stat(root .. "/" .. p) ~= nil
  end, previous)
end

--- Input tokens one file's request sends beyond the shared system prompt: the files it sees (~3k characters each), the
--- API index and the task
---@param file BuildFile
---@return integer
function M.file_estimate(file)
  return require("agent.budget").tokens(1500 + #file.needs * 3000)
end

--- Tokens of the shared system prompt (all four documents + the plan): paid in full once, then read from the cache
---@param plan BuildPlan
---@param docs table<string, string>
---@return integer
function M.shared_estimate(plan, docs)
  local chars = 1200
  for _, f in ipairs(plan.files) do
    chars = chars + #f.path + #f.purpose + 6 + #table.concat(f.exports or {}, " ") + #(f.verifies or "")
  end
  chars = chars + #(plan.summary or "") + #(plan.architecture or "") + #table.concat(plan.decisions or {}, " ")
  for _, text in pairs(docs) do
    chars = chars + #text
  end
  return require("agent.budget").tokens(chars)
end

--- Rough input tokens of the whole build (before the cache: documents shared by many files are paid once)
---@param plan BuildPlan
---@param docs table<string, string>
---@return integer
function M.estimate(plan, docs)
  local total = M.shared_estimate(plan, docs) * #plan.files
  for _, f in ipairs(plan.files) do
    total = total + M.file_estimate(f)
  end
  return total
end

-- ── Models of each phase ─────────────────────────────────────────────────────

-- diagnosis and look: the fixes' model; use: the scenarios and the verdict (worth the strongest model you have)
local ACTION = { plan = "kit_build_plan", files = "kit_build_file", fixes = "kit_build_fix", use = "kit_build_use" }

--- The phases whose model can be chosen, in the order the view lists them (keys 1 2 3 4)
M.TIERED = { "plan", "files", "fixes", "use" }

--- "claude/haiku" for a phase, from its tier (main/light) and what <leader>am chose for that tier
---@param phase "plan"|"files"|"fixes"|"use"
---@return string label, table? sel
function M.model(phase)
  local sel = require("agent.selection").current { name = ACTION[phase], tier = run().tiers[phase] or "main" }
  return sel and require("agent.selection").label(sel) or "no backend", sel
end

--- Dollars per input token of a phase's model, from the history (nil until the model has a price)
---@param phase "plan"|"files"|"fixes"|"use"
---@return number?
function M.price(phase)
  local _, sel = M.model(phase)
  if not sel then
    return nil
  end
  local ok, runs = pcall(function()
    return require("agent.runs.store").read()
  end)
  return require("agent.budget").price_per_token(ok and runs or {}, sel.backend, sel.model)
end

--- The review's numbers again (after a skip or a model change)
function M.reestimate()
  local r = state.run
  if not r or not r.plan or not live.docs then
    return
  end
  local shared = M.shared_estimate(r.plan, live.docs)
  local own, count = 0, 0
  for _, f in ipairs(r.files) do
    f.estimate = shared + M.file_estimate(f)
    if f.state ~= "skipped" and f.state ~= "done" and f.state ~= "fixed" then
      own = own + M.file_estimate(f)
      count = count + 1
    end
  end
  -- with the cache: the shared prompt written once (1.25x), read by every other request (0.1x)
  local equivalent = own + (count > 0 and (shared * 1.25 + shared * 0.1 * (count - 1)) or 0)
  local tokens = own + shared * count
  local price = M.price "files"
  r.estimate = {
    tokens = tokens,
    cost = price and equivalent * price or nil,
    nocache = price and tokens * price or nil,
    files = count,
  }
end

--- What the plan request will roughly cost: the four documents and its instructions, at the plan model's price
---@return { tokens: integer, cost: number? }
function M.plan_estimate()
  local r = state.run
  local chars = 2000
  for _, d in ipairs(r and r.docs or {}) do
    chars = chars + d.chars
  end
  local tokens = require("agent.budget").tokens(chars)
  local price = r and M.price "plan"
  return { tokens = tokens, cost = price and tokens * price or nil }
end

--- Switches a phase between the main and the light tier
---@param phase "plan"|"files"|"fixes"|"use"
function M.cycle(phase)
  local r = state.run
  if not r or r.running then
    return
  end
  r.tiers[phase] = (r.tiers[phase] or "main") == "main" and "light" or "main"
  M.reestimate()
  state.changed()
end

-- ── Running ──────────────────────────────────────────────────────────────────

---@param n integer
---@return string
local function size(n)
  return n >= 1000 and ("%.1fk"):format(n / 1000) or tostring(n)
end

--- Seconds this run has been working (across resumes)
---@return integer
function M.elapsed()
  local r = state.run
  if not r then
    return 0
  end
  return r.elapsed + (live.since and math.floor((vim.uv.hrtime() - live.since) / 1e9) or 0)
end

local function begin()
  run().running = true
  live.since = live.since or vim.uv.hrtime()
  state.changed()
end

local function pause()
  local r = state.run
  if r and live.since then
    r.elapsed = r.elapsed + math.floor((vim.uv.hrtime() - live.since) / 1e9)
  end
  live.since = nil
  if r then
    r.running = false
  end
end

--- The run ends (well or not): the phase stays where it ended, everything is saved, a notice says it even with the tab closed
---@param phase string
---@param outcome string
---@param kind "info"|"fail"?
---@param note string?
local function finish(phase, outcome, kind, note)
  local secs = M.elapsed()
  pause()
  local r = run()
  r.phase, r.outcome, r.current = phase, outcome, nil
  if note then
    state.feed(kind or "info", note)
  end
  record()
  state.save()
  state.changed()
  local msg = ("Build %s: %s · $%.3f · %dm%02ds"):format(
    r.task and (r.name .. " " .. r.task.id) or r.scope and (r.name .. " " .. r.scope) or r.name,
    outcome,
    r.totals.cost,
    math.floor(secs / 60),
    secs % 60
  )
  if kind == "fail" then
    log.warn(msg)
  else
    log.info(msg)
  end
end

--- One request of the build, with its phase's tier, counted in the totals
---@param req table
---@param phase "plan"|"files"|"fixes"|"use"
---@param on_text fun(delta: string)?
---@param cb fun(ok: boolean, text: string, usage: table?, ms: integer)
local function call(req, phase, on_text, cb)
  local t0 = vim.uv.hrtime()
  req.tier = run().tiers[phase] or "main"
  if phase == "fixes" and (live.stuck or 0) > 0 then -- the last round changed nothing: think harder
    req.tier, req.effort = "main", "high"
  end
  req.on_text = on_text
  req.quiet = true -- the build has its own statusline chip
  req.preapproved = phase ~= "plan" -- the review was the yes; the plan request itself is small
  live.handle = require("agent").complete(req, function(ok, text, usage)
    live.handle = nil
    if not run().running then -- stopped meanwhile: the answer is dropped
      return
    end
    state.add_usage(usage)
    cb(ok, text, usage, math.floor((vim.uv.hrtime() - t0) / 1e6))
  end)
end

---@param root string
---@param path string
---@param content string
---@return boolean, string?
local function write_file(root, path, content)
  local full = root .. "/" .. path
  if vim.uv.fs_stat(full) then
    local entry, why = require("files.ops").trash(full)
    if not entry then
      return false, why
    end
  end
  vim.fn.mkdir(vim.fs.dirname(full), "p")
  local f, err = io.open(full, "w")
  if not f then
    return false, err
  end
  f:write(content)
  f:close()
  return true
end

--- "9.8k in · 8.1k cached · 1.2k out · $0.0021 · 6.3s"
---@param usage table?
---@param ms integer?
---@return string
local function usage_text(usage, ms)
  local u = usage or {}
  local parts = { ("%s in"):format(size(u.tokens_in or 0)) }
  if (u.cache_read or 0) > 0 then
    parts[#parts + 1] = ("%s cached"):format(size(u.cache_read))
  end
  parts[#parts + 1] = ("%s out"):format(size(u.tokens_out or 0))
  if u.cost then
    parts[#parts + 1] = ("$%.4f"):format(u.cost)
  end
  parts[#parts + 1] = ("%.1fs"):format((ms or 0) / 1000)
  return table.concat(parts, " · ")
end

--- The texts written so far (read from disk for what an earlier session wrote), over the project's files a layer build
--- builds on: every request sees their API, and a file that needs one sees it whole
---@return table<string, string>
local function written()
  if live.written then
    return live.written
  end
  live.written = {}
  for _, p in ipairs(run().existing or {}) do
    live.written[p] = require("utils.project").read(run().root .. "/" .. p)
  end
  for _, f in ipairs(run().files) do
    if f.state == "done" or f.state == "fixed" then
      live.written[f.path] = require("utils.project").read(run().root .. "/" .. f.path)
    end
  end
  return live.written
end

--- The paths a check's errors and a diagnosis may name: the plan's files, and the project's files a layer build builds on
--- (a domain that needs a dependency fixes the foundation's manifest)
---@return string[]
local function owned()
  local r = run()
  local out = vim.tbl_map(function(f)
    return f.path
  end, r.files)
  for _, p in ipairs(r.existing or {}) do
    if not state.file(p) then
      out[#out + 1] = p
    end
  end
  return out
end

--- The files this build created (what a replan may drop and a clean sends to the trash): not those a layer only changed
---@return string[]
local function created()
  local out = {}
  for _, f in ipairs(run().files) do
    if not f.existed then
      out[#out + 1] = f.path
    end
  end
  return out
end

--- The last request sent for a file (what `p` shows in the view)
---@param path string
---@return { system: string, prompt: string }?
function M.sent(path)
  return live.prompts[path]
end

--- The documents the use phase reads: a feature's scenarios come from its requirement alone (not the whole SPEC.md)
---@return table<string, string>
local function use_docs()
  local r = run()
  if r.scope == "feature" and r.task and live.docs then
    return vim.tbl_extend("force", live.docs, { spec = r.task.text })
  end
  return live.docs
end

--- The build's records for the next person or agent, 0 tokens, never in the build's way: the plan's decisions as an ADR
--- once the review is accepted (agent/kit/adr.lua), PROGRESS.md whenever the run settles (agent/kit/progress.lua)
---@param what "adr"?
record = function(what)
  local settings = require("core.settings").agent.kit.build or {}
  local r = run()
  if what == "adr" and settings.adr ~= false then
    local ok, path = pcall(require("agent.kit.adr").record, r)
    if ok and path then
      state.feed("info", "decisions recorded: " .. path)
    elseif not ok then
      state.feed("fail", "ADR not written: " .. tostring(path))
    end
  end
  if settings.progress ~= false then
    local ok, why = pcall(require("agent.kit.progress").record, r)
    if not ok then
      state.feed("fail", "PROGRESS.md not written: " .. tostring(why))
    end
  end
end

local check, look, use -- forward
---@type table<string, "test"|"subject"> what each file of the coming fix round is (a failing test, the code it tests)
local roles = {}

--- The files a diagnosis (or the look at the screens) named, one request each, code before tests; then the checks again
---@param list { path: string, change: string }[]
---@param note string what is wrong, for every file
---@param blamed table<string, string[]> the errors per file (a file with none gets `head`)
---@param head string
local function fix_files(list, note, blamed, head)
  local r = run()
  table.sort(list, function(x, y) -- the code first, then the tests that check it
    local tx, ty = verify.is_test(x.path) and 1 or 0, verify.is_test(y.path) and 1 or 0
    if tx ~= ty then
      return tx < ty
    end
    return x.path < y.path
  end)
  local i = 0
  local function next_fix()
    i = i + 1
    local item = list[i]
    if not r.running then
      return
    end
    if not item then
      live.autofixed = {} -- new code may need the formatter again: it is free, the model's round is not
      return check()
    end
    local path = item.path
    if item.new and not state.file(path) then -- a file the plan missed (an embedded asset): planned now, then written
      local entry =
        { path = path, purpose = item.change, exports = {}, docs = { "spec", "stack", "design" }, needs = {} }
      table.insert(r.plan.files, entry)
      table.insert(r.files, vim.tbl_extend("force", entry, { state = "pending" }))
      state.feed("info", path .. " · a file the plan missed, added")
    end
    local file = state.file(path)
    local role = verify.is_test(path) and "test" or (roles[path] or (not blamed[path] and "subject") or nil)
    local errors = blamed[path] and table.concat(blamed[path], "\n") or head
    local before = written()[path] or ""
    local req = prompt.fix(
      path,
      before,
      errors,
      file,
      r.plan,
      live.docs,
      written(),
      role,
      (note ~= "" or item.change ~= "") and (note .. (item.change ~= "" and ("\nIn this file: " .. item.change) or ""))
        or nil
    )
    live.prompts[path] = { system = req.system, prompt = req.prompt }
    r.current = path
    if file then
      file.state = "writing"
    end
    state.feed("in", path, ("%s · %s chars"):format(role or "named in the errors", size(#req.system + #req.prompt)))
    view().code_start(path, "fixing")
    local settle -- what the answer becomes (below): a refused test, a written fix, an unchanged file
    local function ask(request, retried)
      call(request, "fixes", view().code_stream, function(ok, text, usage, ms)
        if not ok then
          if file then
            file.state = "failed"
          end
          return finish("failed", "✗ the fix of " .. path .. " failed", "fail", text)
        end
        local content, bad, whole
        if edits.unchanged(text) then
          content = before
        elseif edits.has(text) then
          content, bad = edits.apply(before, text)
          bad = bad and ("its edit blocks do not apply (" .. bad .. ")")
          whole = bad ~= nil
        else
          content = prompt.content(text, path)
          bad = clean.problem(content, path) or edits.shrunk(before, content)
        end
        -- a file the diagnosis said how to change, answered as right as it is (a test may well be)
        if not bad and content == before and item.change ~= "" and role ~= "test" then
          bad = "it changed nothing, and the change asked for in this file is: " .. item.change
        end
        if bad and not retried then
          state.feed("info", ("%s: %s · asked again"):format(path, bad), usage_text(usage, ms))
          view().code_start(path, "asking again")
          return ask(prompt.again(request, bad, whole), true)
        elseif bad then -- a broken answer must not replace a file that was a file
          state.feed("fail", ("%s: %s · the file stays as it was"):format(path, bad), usage_text(usage, ms))
          content = before ~= "" and before or (content or "")
        end
        return settle(content, usage, ms)
      end)
    end
    settle = function(content, usage, ms)
      local weaker = verify.is_test(path) and verify.weakened(before, content)
      if weaker then -- the test stays as it was: the fix must come from the code
        if file then
          file.state = "done"
        end
        state.feed("fail", ("%s: fix refused, %s"):format(path, weaker), usage_text(usage, ms))
        return next_fix()
      end
      if content ~= before then
        local done, why = write_file(r.root, path, content)
        if not done then
          return finish("failed", "✗ could not write " .. path, "fail", tostring(why))
        end
        written()[path] = content
      end
      if file then
        file.state, file.lines = content ~= before and "fixed" or "done", select(2, content:gsub("\n", ""))
        file.cost = (file.cost or 0) + (usage and usage.cost or 0)
      end
      view().code_done(path, content, content ~= before and "fixed" or "unchanged")
      state.feed("out", path .. (content ~= before and "" or " · unchanged"), usage_text(usage, ms))
      state.save()
      next_fix()
    end
    ask(req, false)
  end
  next_fix()
end

-- fix: diagnose first (one request with everything in view), then each file the diagnosis names with its instruction;
-- a fix that weakens a test is refused (the test stays as it was)
---@param blamed table<string, string[]>
---@param output string the failing check's output
local function fix(blamed, output)
  local r = run()
  r.fix_round = r.fix_round + 1
  r.phase = "fix"
  local planned = owned()
  state.feed("step", ("round %d · diagnosing"):format(r.fix_round), M.model "fixes", "Fix")
  local dreq = diagnose.request(output, blamed, r.plan, live.docs, written(), live.user)
  live.prompts["diagnosis"] = { system = dreq.system, prompt = dreq.prompt }
  state.feed(
    "in",
    "diagnosis",
    ("%d file%s named · %s chars"):format(
      vim.tbl_count(blamed),
      vim.tbl_count(blamed) == 1 and "" or "s",
      size(#dreq.system + #dreq.prompt)
    )
  )
  call(dreq, "fixes", nil, function(dok, dtext, dusage, dms)
    local plan = dok and diagnose.parse(dtext, planned)
    local list = {} ---@type { path: string, change: string }[]
    local note = ""
    if plan then
      note = plan.diagnosis
      list = plan.files
      state.feed("out", "diagnosis · " .. plan.diagnosis, usage_text(dusage, dms))
      for _, f in ipairs(list) do
        state.feed("info", f.path .. ": " .. f.change)
      end
    else
      for path in pairs(blamed) do
        list[#list + 1] = { path = path, change = "" }
      end
      state.feed("info", "no usable diagnosis: fixing the files the errors name")
    end
    local head = table.concat(vim.list_slice(vim.split(vim.trim(output), "\n", { plain = true }), 1, 40), "\n")
    fix_files(list, note, blamed, head)
  end)
end

--- Every check passes and the user phases are over: the outcome says what the user phase found
---@param note string
local function done(note)
  local r = run()
  local u = r.use or {}
  local outcome = ("✓ built · %d files · checks pass"):format(state.progress())
  local kind = "info"
  if u.total and u.passed == u.total and (u.issues or 0) == 0 then
    outcome = outcome .. (" · used %d/%d"):format(u.passed, u.total)
  elseif u.total and u.passed == u.total then -- every step showed what it must, the verdict still names problems
    outcome = ("⚠ built · %d files · checks pass · used %d/%d · %d issue%s"):format(
      state.progress(),
      u.passed,
      u.total,
      u.issues,
      u.issues == 1 and "" or "s"
    )
    kind, note = "fail", note .. " · the issues the verdict found are in the feed"
  elseif u.total then
    outcome = ("⚠ built · %d files · checks pass · used %d/%d"):format(state.progress(), u.passed, u.total)
    kind, note = "fail", note .. " · what still fails for the user is in the feed"
  end
  finish("done", outcome, kind, note)
end

--- The golden snapshots follow the code: to the trash before a fix, written again by the checks (and looked at again)
local function drop_goldens()
  local r = run()
  for _, p in ipairs(look_mod.goldens(r.root)) do
    require("files.ops").trash(r.root .. "/" .. p)
  end
  r.looked, r.looks = nil, 0
  live.autofixed = {} -- the golden update may run again
end

--- Every check passes and the app was used: the rendered screens against DESIGN.md (Go TUIs, whose teatest golden files
--- are the screens as the terminal shows them). What differs is fixed like a diagnosis' files, the golden files go to
--- the trash so the checks write them again from the fixed code, and those are looked at again: `look_rounds` looks at
--- most (2: one fix, verified); the last one only reports.
look = function()
  local r = run()
  local settings = require("core.settings").agent.kit.build or {}
  local renders = {}
  if settings.look ~= false and not r.looked and live.docs and live.docs.design then
    renders = look_mod.renders(r.root)
  end
  if #renders == 0 then
    return done "every check passes · ⏎ opens a file"
  end
  r.looks = (r.looks or 0) + 1
  local last = r.looks >= (settings.look_rounds or 2)
  local planned = owned()
  state.feed(
    "step",
    ("%d screen%s against DESIGN.md · look %d"):format(#renders, #renders == 1 and "" or "s", r.looks),
    M.model "fixes",
    "Look"
  )
  local req = look_mod.request(renders, r.plan, live.docs, written())
  live.prompts["look"] = { system = req.system, prompt = req.prompt }
  state.feed(
    "in",
    "look",
    ("%s · %s chars"):format(
      table.concat(
        vim.tbl_map(function(x)
          return vim.fs.basename(x.path)
        end, renders),
        ", "
      ),
      size(#req.system + #req.prompt)
    )
  )
  call(req, "fixes", nil, function(ok, text, usage, ms)
    local diff = ok and look_mod.parse(text, planned)
    if not diff then
      r.looked = true -- a recheck stays at 0 tokens unless a check fails
      state.feed("out", "look · the screens match DESIGN.md", usage_text(usage, ms))
      return done "every check passes and the screens match DESIGN.md · ⏎ opens a file"
    end
    state.feed("out", "look · " .. diff.diagnosis, usage_text(usage, ms))
    if last then
      r.looked = true
      for _, f in ipairs(diff.files) do
        state.feed("fail", f.path .. ": " .. f.change)
      end
      return done(("the screens still differ from DESIGN.md after %d looks"):format(r.looks))
    end
    local blamed = {}
    for _, f in ipairs(diff.files) do
      state.feed("info", f.path .. ": " .. f.change)
      blamed[f.path] = { "The screen does not match DESIGN.md: " .. f.change }
    end
    local looks = r.looks
    drop_goldens()
    r.looks = looks -- this round counts: the next look is the one that checks the fix
    roles = {}
    r.phase = "fix"
    local shown = table.concat(
      vim.tbl_map(function(x)
        return ("%s:\n%s"):format(x.path, x.text)
      end, renders),
      "\n\n"
    )
    r.fix_round, live.stuck, live.last_signature = 0, 0, nil -- a repair of its own: fresh rounds
    fix_files(diff.files, diff.diagnosis, blamed, shown)
  end)
end

--- The app used like its user would (use/): its scenarios (written once from SPEC.md and DESIGN.md, replayed every
--- round), performed by the driver of its kind, every frame checked for free, one verdict request; what fails for the
--- user is fixed like a diagnosis' files and the same scenarios run again: `use_rounds` fixes at most, the last play
--- only reports. An app that cannot be driven here (no driver, no tmux/Playwright/device) skips to the look, at 0 tokens.
use = function()
  local r = run()
  local settings = require("core.settings").agent.kit.build or {}
  r.use = r.use or { fixes = 0 }
  if settings.use == false or r.use.done or not r.plan then
    return look()
  end
  if not scopes.get(r.scope).use or not (live.docs and live.docs.spec) then -- no interface yet, or nothing to try
    r.use.done = true
    return look()
  end
  local use_mod = require "agent.kit.build.use"
  local scenario = require "agent.kit.build.use.scenario"
  local judge = require "agent.kit.build.use.judge"
  local stack = live.docs and live.docs.stack
  local ctx, why = use_mod.ready(r.root, stack, verify.package_manager_hint(stack))
  if not ctx then
    state.feed("info", "use · skipped: " .. tostring(why))
    r.use.done = true
    return look()
  end
  local kind = ctx.launch.kind
  local planned = owned()
  r.phase = "use"

  local function judged(results)
    live.user = nil -- the app was used again: what the user met is in this verdict
    local passed, total = judge.tally(results)
    r.use.passed, r.use.total, r.use.dir = passed, total, ctx.dir
    local failures = 0
    for _, x in ipairs(results) do
      failures = failures + x.failures
    end
    for _, l in ipairs(use_mod.lines(results)) do
      state.feed(l.ok and "info" or "fail", l.text)
    end
    state.feed("info", "frames and screenshots: " .. ctx.dir)
    local _, values = wiring.split(wiring.find(r.plan, written()))
    local req = judge.request(
      results,
      wiring.report(values),
      r.plan,
      use_docs(),
      scenario.controls(written(), r.plan),
      prompt.api(written())
    )
    live.prompts["use"] = { system = req.system, prompt = req.prompt }
    state.feed(
      "in",
      "use",
      ("%d/%d scenarios pass the checks · %s chars"):format(passed, total, size(#req.system + #req.prompt))
    )
    local function on_verdict(ok, text, usage, ms, retried)
      local verdict = ok and judge.parse(text, planned, failures)
      if not verdict and ok and not retried then -- one more request beats a verdict lost to a stray brace
        state.feed("info", "use · the verdict was not valid JSON · asked again", usage_text(usage, ms))
        return call(prompt.again(req, "it was not one valid JSON object"), "use", nil, function(o, t, u, m)
          on_verdict(o, t, u, m, true)
        end)
      end
      if not verdict then
        state.feed("out", "use · no usable verdict", usage_text(usage, ms))
        r.use.done = true
        return look()
      end
      r.use.issues = #vim.tbl_filter(function(i)
        return i.severity ~= "minor"
      end, verdict.issues)
      state.feed(
        "out",
        "use · " .. (verdict.pass and "the user gets what SPEC.md promises" or verdict.diagnosis),
        usage_text(usage, ms)
      )
      for _, i in ipairs(verdict.issues) do
        state.feed(
          i.severity == "minor" and "info" or "fail",
          ("%s · scenario %d step %d: %s"):format(i.severity, i.scenario, i.step, i.problem)
        )
      end
      if verdict.pass then
        r.use.done = true
        state.save()
        return look()
      end
      if #verdict.files == 0 or r.use.fixes >= (settings.use_rounds or 2) then
        r.use.done = true
        state.save()
        return look()
      end
      r.use.fixes = r.use.fixes + 1
      local blamed, failing = {}, {}
      for _, f in ipairs(verdict.files) do
        state.feed("info", f.path .. ": " .. f.change)
        blamed[f.path] = { "A user trying the app meets this: " .. f.change }
      end
      for _, l in ipairs(use_mod.lines(results)) do
        if not l.ok then
          failing[#failing + 1] = l.text
        end
      end
      for _, i in ipairs(verdict.issues) do
        if i.severity ~= "minor" then
          failing[#failing + 1] = ("%s: %s"):format(i.severity, i.problem)
        end
      end
      drop_goldens() -- the screens change: their snapshots are written again, and looked at
      roles = {}
      r.phase = "fix"
      -- a repair of its own: fresh rounds, and every diagnosis until the app is used again knows what the user met
      r.fix_round, live.stuck, live.last_signature = 0, 0, nil
      live.user = table.concat(failing, "\n")
      fix_files(verdict.files, verdict.diagnosis, blamed, table.concat(failing, "\n"))
    end
    call(req, "use", nil, function(ok, text, usage, ms)
      on_verdict(ok, text, usage, ms, false)
    end)
  end

  local function play(list)
    r.phase = "use"
    local round = (r.use.plays or 0) + 1
    r.use.plays = round
    state.feed("step", ("%s · %d scenarios · play %d"):format(ctx.launch.what, #list, round), "0 tokens", "Use")
    use_mod.play(ctx, list, {
      round = round,
      cancelled = function()
        return not run().running
      end,
      progress = function(text)
        r.current = text
        state.changed()
      end,
    }, function(results, err)
      r.current = nil
      if not run().running then
        return
      end
      if not results then
        state.feed("fail", "use · " .. tostring(err))
        r.use.done, r.use.error = true, err
        return look()
      end
      judged(results)
    end)
  end

  if r.use.scenarios and r.use.kind == kind then
    return play(r.use.scenarios)
  end
  local req = scenario.request(kind, r.plan, use_docs(), written())
  live.prompts["scenarios"] = { system = req.system, prompt = req.prompt }
  state.feed("step", "what a user will try, from SPEC.md and DESIGN.md", M.model "use", "Use")
  state.feed("in", "scenarios", ("%s · %s chars"):format(kind, size(#req.system + #req.prompt)))
  local function on_scenarios(ok, text, usage, ms, retried)
    local list = ok and scenario.parse(text, kind)
    if not list and ok and not retried then -- one more request beats a whole phase lost to a stray brace
      state.feed("info", "scenarios · not valid JSON · asked again", usage_text(usage, ms))
      return call(
        prompt.again(req, "it was not one valid JSON object with a `scenarios` list"),
        "use",
        nil,
        function(o, t, u, m)
          on_scenarios(o, t, u, m, true)
        end
      )
    end
    if not list then
      state.feed("out", "scenarios · none usable · the use phase is skipped", usage_text(usage, ms))
      r.use.done = true
      return look()
    end
    local steps = 0
    for _, sc in ipairs(list) do
      steps = steps + #sc.steps
    end
    r.use.scenarios, r.use.kind = list, kind
    state.feed("out", ("scenarios · %d, %d steps"):format(#list, steps), usage_text(usage, ms))
    for _, sc in ipairs(list) do
      state.feed("info", ("%s%s"):format(sc.name, #sc.covers > 0 and (" · " .. table.concat(sc.covers, " ")) or ""))
    end
    state.save()
    play(list)
  end
  call(req, "use", nil, function(ok, text, usage, ms)
    on_scenarios(ok, text, usage, ms, false)
  end)
end

-- check: the manifest's own tools
check = function()
  local r = run()
  r.phase, r.current = "check", nil
  local checks = verify.checks(r.root, verify.package_manager_hint(live.docs and live.docs.stack))
  -- after the tools: a name the plan promised to others that only its own file (or a test) uses (not for a foundation or
  -- a domain: nothing calls them yet by design)
  if r.plan and scopes.get(r.scope).wiring then
    checks[#checks + 1] = {
      label = "the interface uses what the plan exports",
      fn = function()
        local calls = wiring.split(wiring.find(r.plan, written()))
        return #calls == 0, wiring.report(calls)
      end,
    }
  end
  r.checks = vim.tbl_map(function(c)
    return { label = c.label, state = "pending" }
  end, checks)
  local labels = vim.tbl_map(function(c)
    return c.label
  end, checks)
  state.feed("step", table.concat(labels, " · "), "0 tokens", "Check")
  verify.run(r.root, checks, function(i, ok)
    if r.checks[i] then
      r.checks[i].state = ok and "done" or "failed"
    end
    state.changed()
  end, function(ok, output, failed)
    if not r.running then
      return
    end
    if ok then
      remember(r.root, r.scope, created())
      return use()
    end
    local fixer = failed and failed.autofix
    if type(fixer) == "function" then
      fixer = fixer(output or "")
    end
    if fixer and not live.autofixed[failed.label] then -- a tool fixes it, no model (once: what it cannot fix goes on)
      live.autofixed[failed.label] = true
      vim.system(fixer, { cwd = r.root }):wait()
      local golden = table.concat(fixer, " "):find("-update", 1, true)
      state.feed(
        "info",
        table.concat(fixer, " ") .. (golden and " · first golden files: review testdata/*.golden" or " · 0 tokens")
      )
      return check()
    end
    state.feed("fail", failed and failed.label or "check", (output or ""):sub(1, 1200))
    local planned = owned()
    local outside = vim.tbl_filter(function(p) -- only the project's own (not a library's file in a stack trace)
      return vim.uv.fs_stat(r.root .. "/" .. p) ~= nil
    end, verify.outside(output or "", planned))
    if #outside > 0 then
      state.feed("info", "errors in files this build did not write: " .. table.concat(outside, ", "))
    end
    local gomod = require("utils.project").read(r.root .. "/go.mod") or ""
    local blamed = verify.blame(output or "", planned, gomod:match "^module%s+(%S+)" or gomod:match "\nmodule%s+(%S+)")
    roles = {}
    -- the manifest only when the tool itself did not run (no test failed, no file named)
    local tests_failed = (output or ""):find "%-%-%- FAIL" or (output or ""):find "FAIL:" or (output or ""):find "✗"
    local manifest = next(blamed) == nil and not tests_failed and verify.manifest_of(planned)
    if manifest then -- no file named: the tool did not run, the manifest lacks something
      local lines = vim.split(vim.trim(output or ""), "\n", { plain = true })
      blamed[manifest] = vim.list_slice(lines, 1, 40)
      state.feed(
        "info",
        ("no file named in the errors: %s goes back with them (a tool that does not run is a missing dependency)"):format(
          manifest
        )
      )
    end
    -- a failing test: the code it exercises goes too (the bug is often there, not in the test)
    for _, path in ipairs(vim.tbl_keys(blamed)) do
      if verify.is_test(path) then
        roles[path] = "test"
        local file = state.file(path)
        for _, subject in ipairs(file and file.needs or {}) do
          if not blamed[subject] and not verify.is_test(subject) and not verify.is_manifest(subject) then
            blamed[subject], roles[subject] = blamed[path], "subject"
          end
        end
      end
    end
    if next(blamed) == nil then
      return finish(
        "failed",
        "✗ " .. (failed and failed.label or "a check") .. " failed",
        "fail",
        "no planned file is named: fix it by hand or ask the agent"
      )
    end
    -- rounds go on while they make progress (the failure changes); they stop after `max_fixes` rounds in a row that
    -- change nothing, or at the hard cap. A round that changed nothing escalates the next one (main tier, more effort).
    local signature = M.signature(failed and failed.label or "", output or "")
    if live.last_signature == signature then
      live.stuck = (live.stuck or 0) + 1
    else
      live.stuck = 0
    end
    live.last_signature = signature
    if live.stuck >= r.max_fixes then
      return finish(
        "failed",
        ("✗ no progress in %d fix rounds (%d in all)"):format(live.stuck, r.fix_round),
        "fail",
        "the same failure came back: Enter tries again with fresh rounds, or fix it by hand"
      )
    end
    if r.fix_round >= M.MAX_ROUNDS then
      return finish("failed", ("✗ still failing after %d fix rounds"):format(r.fix_round), "fail")
    end
    if r.fix_round > 0 then
      state.feed(
        "info",
        live.stuck > 0 and "the same failure: the next round escalates (main tier, more effort)"
          or "progress: the failure changed, another round"
      )
    end
    fix(blamed, output or "")
  end)
end

-- write: one file at a time, skipping what is done (a resumed run) or skipped
local function write()
  local r = run()
  r.phase = "write"
  r.looked, r.looks = nil, 0 -- new code: its screens get a look
  if r.use then -- and a user: the same scenarios (they come from the documents), fresh rounds
    r.use = { fixes = 0, scenarios = r.use.scenarios, kind = r.use.kind }
  end
  live.stuck, live.last_signature, live.user = 0, nil, nil
  begin()
  local i = 0
  local function next_file()
    i = i + 1
    if not r.running then
      return
    end
    local file = r.files[i]
    if not file then
      state.save()
      return check()
    end
    if file.state == "done" or file.state == "fixed" or file.state == "skipped" then
      return next_file()
    end
    local req = prompt.file(file, r.plan, live.docs, written())
    live.prompts[file.path] = { system = req.system, prompt = req.prompt }
    file.state, r.current = "writing", file.path
    file.sent, file.api = #req.system + #req.prompt, #prompt.api(written(), file.path)
    local sees = #file.needs > 0 and (" · sees " .. table.concat(file.needs, ", ")) or ""
    state.feed(
      "in",
      file.path,
      ("%s · plan · api %s%s · %s chars"):format(table.concat(file.docs, " "), size(file.api), sees, size(file.sent))
    )
    view().code_start(file.path)
    local spent = { tokens_in = 0, tokens_out = 0, cache_read = 0, cost = 0, ms = 0 }
    local function ask(request, retried)
      call(request, "files", view().code_stream, function(ok, text, usage, ms)
        if not ok and not retried and tostring(text):find("timed out", 1, true) then -- once: a slow answer is not a wrong one
          state.feed("info", ("%s: %s · asked again"):format(file.path, tostring(text)))
          return ask(request, true)
        end
        if not ok then
          file.state = "failed"
          return finish(
            "stopped",
            "✗ " .. file.path .. " failed",
            "fail",
            tostring(text) .. " · Enter resumes from this file"
          )
        end
        local u = usage or {}
        spent.tokens_in, spent.tokens_out = spent.tokens_in + (u.tokens_in or 0), spent.tokens_out + (u.tokens_out or 0)
        spent.cache_read, spent.cost = spent.cache_read + (u.cache_read or 0), spent.cost + (u.cost or 0)
        spent.ms = spent.ms + ms
        local content = prompt.content(text, file.path)
        local bad = clean.problem(content, file.path)
        if bad and not retried then -- one more request now beats a check, a diagnosis and a rewrite later
          state.feed("info", ("%s: %s · asked again"):format(file.path, bad), usage_text(usage, ms))
          view().code_start(file.path, "asking again")
          return ask(prompt.again(request, bad), true)
        elseif bad then
          state.feed("fail", ("%s: %s · written as it is (the checks will say what is wrong)"):format(file.path, bad))
        end
        local done, why = write_file(r.root, file.path, content)
        if not done then
          file.state = "failed"
          return finish("stopped", "✗ could not write " .. file.path, "fail", tostring(why))
        end
        written()[file.path] = content
        file.state, file.lines = "done", select(2, content:gsub("\n", ""))
        file.tokens_in, file.tokens_out, file.cached, file.cost, file.ms =
          spent.tokens_in, spent.tokens_out, spent.cache_read, spent.cost, spent.ms
        file.model = M.model "files"
        view().code_done(file.path, content)
        state.feed("out", ("%s · %d lines"):format(file.path, file.lines), usage_text(usage, ms))
        state.save()
        next_file()
      end)
    end
    ask(req, false)
  end
  next_file()
end

-- plan: one request
local function plan()
  local r = run()
  r.phase = "plan"
  begin()
  local s = scopes.get(r.scope)
  -- a layer builds on what is there (without what this scope wrote last time: its new plan replaces that)
  local existing = s.existing and scopes.existing(r.root, not s.additive and M.previous(r.root, r.scope) or nil) or {}
  r.existing = vim.tbl_keys(existing)
  table.sort(r.existing)
  live.written = existing
  -- the decisions earlier builds accepted (their ADRs): the plan follows them, or says which one it supersedes
  local adr = require "agent.kit.adr"
  local decisions = adr.summary(adr.read(r.root))
  local req = plan_mod.request(live.docs, r.scope, existing, r.task, decisions)
  live.prompts["plan.json"] = { system = req.system, prompt = req.prompt }
  local read = vim.tbl_filter(function(id)
    return live.docs[id] ~= nil
  end, plan_mod.DOCS)
  state.feed(
    "step",
    s.from
        and ("%s from %s · on %d existing file%s"):format(s.label, s.from, #r.existing, #r.existing == 1 and "" or "s")
      or "the documents become a list of files",
    M.model "plan",
    "Plan"
  )
  local followed = select(2, decisions:gsub("\nADR %d+ · ", ""))
  state.feed(
    "in",
    "plan",
    ("%s%s · %s chars"):format(
      table.concat(read, " "),
      followed > 0 and (" · follows %d ADR%s"):format(followed, followed == 1 and "" or "s") or "",
      size(#req.system + #req.prompt)
    )
  )
  view().code_start("plan.md", "planning")
  -- the plan read while it is made: first the model's thinking (a long plan thinks for a minute before writing), then the
  -- JSON that has arrived, rendered as plan.md (what is complete so far); a 1 s tick keeps the clock moving in between
  local so_far, thought, thinks, last_draw, t_plan = "", "", 0, 0, vim.uv.hrtime()
  -- what the model was given, shown while it thinks (the claude CLI streams the thinking without its text)
  local given = { "## Read", "" }
  for _, d in ipairs(M.doc_sizes(live.docs, r.scope)) do
    given[#given + 1] = ("- %s · %s chars"):format(d.file, size(d.chars))
  end
  vim.list_extend(given, {
    "",
    "## Next",
    "",
    "- how it works, the architecture and the decisions",
    "- the files in the order they are written: what each exports, verifies and uses",
  })
  given = table.concat(given, "\n")
  local function draw(force)
    local now = vim.uv.hrtime()
    if not force and (now - last_draw) / 1e6 < 150 then
      return
    end
    last_draw = now
    local secs = math.floor((now - t_plan) / 1e9)
    if so_far == "" then
      local doing = thinks > 0 and ("thinking · %d step%s"):format(thinks, thinks == 1 and "" or "s")
        or "waiting for the model"
      local head = ("> %s · %ds · %s\n\n"):format(doing, secs, M.model "plan")
      local body = vim.trim(thought) ~= "" and vim.trim(thought) or given
      return view().code_live("plan.md", head .. body .. "\n")
    end
    local partial = plan_mod.partial(so_far)
    local head = ("> planning · %d file%s so far · %ds · %s\n\n"):format(
      #partial.files,
      #partial.files == 1 and "" or "s",
      secs,
      M.model "plan"
    )
    view().code_live("plan.md", head .. M.plan_text(partial))
  end
  local tick = vim.uv.new_timer()
  local function stop_tick()
    if tick and not tick:is_closing() then
      tick:stop()
      tick:close()
    end
  end
  tick:start(
    1000,
    1000,
    vim.schedule_wrap(function()
      if not run().running or run().phase ~= "plan" then
        return stop_tick()
      end
      draw(true)
    end)
  )
  draw(true)
  req.on_think = function(delta)
    thought, thinks = thought .. delta, thinks + 1
    draw(thinks == 1)
  end
  call(req, "plan", function(delta)
    local first = so_far == ""
    so_far = so_far .. delta
    draw(first) -- the thinking gives way to the plan at once
  end, function(ok, text, usage, ms)
    stop_tick()
    if not ok then
      return finish("ready", "✗ the plan failed", "fail", text)
    end
    local parsed, why = plan_mod.parse(text, existing, r.scope)
    if parsed then
      parsed.task = r.task -- every file request names the requirement or recipe (prompt.system)
    end
    if not parsed then
      return finish("ready", "✗ the plan failed", "fail", why)
    end
    r.plan = parsed
    r.files = vim.tbl_map(function(f)
      -- `existed`: a file of the project a layer changes (never this build's own: a replan or a clean keeps it)
      return vim.tbl_extend("force", f, { state = "pending", existed = existing[f.path] ~= nil or nil })
    end, parsed.files)
    r.stale = not s.additive and M.stale(r.root, M.previous(r.root, r.scope), parsed) or {}
    r.replaced = #vim.tbl_filter(function(f)
      return vim.uv.fs_stat(r.root .. "/" .. f.path) ~= nil
    end, parsed.files)
    state.feed("out", ("plan · %d files"):format(#parsed.files), usage_text(usage, ms))
    view().code_done("plan.md", M.plan_text(parsed), "planned")
    M.reestimate()
    pause()
    r.phase = "review"
    live.review_at = vim.uv.hrtime()
    if live.replanning then -- the screen says it is a new plan, not only a new list
      r.outcome, live.replanning = "■ new plan · review it · ⏎ builds", false
    end
    state.save()
    state.changed()
  end)
end

--- The plan as the code pane shows it: one block per file (what it holds, its documents, what it uses)
---@param plan BuildPlan
---@return string
function M.plan_text(plan)
  local out = { "# Plan · " .. plan.name, "" }
  local function para(title, text)
    if text and text ~= "" then
      vim.list_extend(out, { "## " .. title, "", text, "" })
    end
  end
  para("How it works", plan.summary)
  para("Architecture", plan.architecture)
  if plan.decisions and #plan.decisions > 0 then
    out[#out + 1] = "## Decisions"
    out[#out + 1] = ""
    for _, d in ipairs(plan.decisions) do
      out[#out + 1] = "- " .. d
    end
    out[#out + 1] = ""
  end
  if plan.wiring and #plan.wiring > 0 then
    out[#out + 1] = "## Wiring (what the user does → what runs → what they see)"
    out[#out + 1] = ""
    for _, w in ipairs(plan.wiring) do
      out[#out + 1] = ("- **%s** %s → `%s` → %s"):format(w.req, w.action, w.code:gsub("`", ""), w.shows)
    end
    out[#out + 1] = ""
  end
  out[#out + 1] = ("## Files (%d, in the order they are written)"):format(#plan.files)
  local dir
  for i, f in ipairs(plan.files) do
    local here = vim.fs.dirname(f.path)
    if here ~= dir then
      dir = here
      vim.list_extend(out, { "", "### " .. (here == "." and "(root)" or here) })
    end
    vim.list_extend(out, { "", ("%d. **%s** · %s"):format(i, vim.fs.basename(f.path), f.purpose) })
    for _, e in ipairs(f.exports or {}) do
      out[#out + 1] = "   - `" .. e:gsub("`", "") .. "`"
    end
    if f.verifies then
      out[#out + 1] = "   - verifies: " .. f.verifies
    end
    local meta = "   - reads " .. table.concat(f.docs, " ")
    if #f.needs > 0 then
      meta = meta .. " · uses " .. table.concat(f.needs, ", ")
    end
    out[#out + 1] = meta
  end
  return table.concat(out, "\n") .. "\n"
end

-- ── What the view's keys call ────────────────────────────────────────────────

--- Enter: the next step from where the run stands (ready → plan, review → write, stopped → resume)
function M.go()
  local r = state.run
  if not r or r.running then
    return
  end
  if r.phase == "done" then
    return log.info "Build: done · r checks again · n plans a new build"
  end
  live.docs = live.docs or M.docs(r.root, r.scope)
  r.outcome = nil
  if r.phase == "ready" or not r.plan then
    return plan()
  end
  if r.phase == "review" then
    -- the review is the confirmation: an Enter that arrives right as it appears (typed ahead, pressed twice) is not one
    if live.review_at and (vim.uv.hrtime() - live.review_at) / 1e9 < 1.5 then
      return log.info "Build: this is the review · press Enter again to build"
    end
    for _, p in ipairs(r.stale or {}) do
      require("files.ops").trash(r.root .. "/" .. p)
    end
    if r.stale and #r.stale > 0 then
      local n = #r.stale
      state.feed(
        "info",
        ("%d file%s of the previous build to the trash: %s"):format(
          n,
          n == 1 and "" or "s",
          table.concat(r.stale, ", ")
        )
      )
      r.stale = {}
    end
    remember(r.root, r.scope, created())
    record "adr"
    local _, total = state.progress()
    local est = r.estimate and r.estimate.cost and ("~$%.3f before the cache"):format(r.estimate.cost) or nil
    state.feed("step", ("%d files · %s"):format(total, M.model "files"), est, "Write")
    return write()
  end
  -- stopped, failed, done with failures: go on from where it stands
  local pending = false
  for _, f in ipairs(r.files) do
    if f.state == "writing" or f.state == "failed" then
      f.state = "pending"
    end
    pending = pending or f.state == "pending"
  end
  if pending then
    state.feed("step", "from the first file not written", M.model "files", "Resume")
    return write()
  end
  r.fix_round, live.autofixed = 0, {}
  live.stuck, live.last_signature = 0, nil
  begin()
  check()
end

--- `r`: the checks (and fix rounds) again on the files as they are now
function M.recheck()
  local r = state.run
  if not r or r.running or not r.plan then
    return log.info "Build: nothing to check (the build has no plan yet)"
  end
  live.docs = live.docs or M.docs(r.root, r.scope)
  live.written = nil
  r.fix_round, live.autofixed, r.outcome = 0, {}, nil
  live.stuck, live.last_signature = 0, nil
  state.feed("step", "the files as they are now", "0 tokens unless a fix is needed", "Check again")
  begin()
  check()
end

--- `x`: stops what is running (the request in flight is killed); Enter resumes
function M.stop()
  local r = state.run
  if not r or not r.running then
    return
  end
  if live.handle then
    pcall(function()
      live.handle:kill(15)
    end)
    live.handle = nil
  end
  for _, f in ipairs(r.files) do
    if f.state == "writing" then
      f.state = "pending"
    end
  end
  finish("stopped", "■ stopped", "info", "stopped · Enter resumes from where it was")
end

--- `x` on a file in the review: leave it out (or back in)
---@param path string
function M.toggle_skip(path)
  local r = state.run
  local f = state.file(path)
  if not r or r.running or not f or (r.phase ~= "review" and r.phase ~= "stopped") then
    return
  end
  if f.state == "skipped" then
    f.state = "pending"
  elseif f.state == "pending" then
    f.state = "skipped"
  end
  M.reestimate()
  state.changed()
end

--- A fresh run of the same project, keeping the models and the rounds you chose (nothing saved is touched)
---@return BuildRun?
local function fresh_run()
  local r = state.run
  if not r or r.running then
    return nil
  end
  local docs = M.docs(r.root, r.scope)
  live.docs, live.written, live.prompts, live.autofixed = docs, nil, {}, {}
  live.stuck, live.last_signature, live.review_at = 0, nil, nil
  local tiers, max = r.tiers, r.max_fixes
  local new = state.new(r.root, M.doc_sizes(docs, r.scope), r.scope, r.task)
  new.tiers, new.max_fixes = tiers, max
  return new
end

--- `n`: a new plan, now (the files the old one wrote stay; the new review says which it replaces or drops)
function M.restart()
  local had = state.run and state.run.plan
  if not fresh_run() then
    return
  end
  state.feed("step", had and "the previous plan is replaced" or "a plan from the documents", nil, "Replan")
  live.replanning = had and true or false
  plan()
end

--- `X`: undo the build: the files it wrote go to the trash (`<leader>Fu` brings them back), the saved run and the list
--- of written files are forgotten, the pre-flight is left. Asks first, with the count.
function M.clean()
  local r = state.run
  if not r or r.running then
    return log.info "Build: stop it first (x)"
  end
  local paths, seen = {}, {}
  local function add(p)
    if p and not seen[p] and vim.uv.fs_stat(r.root .. "/" .. p) then
      seen[p] = true
      paths[#paths + 1] = p
    end
  end
  for _, f in ipairs(r.files) do
    if not f.existed and (f.state == "done" or f.state == "fixed" or f.state == "failed" or f.state == "writing") then
      add(f.path)
    end
  end
  for _, p in ipairs(M.previous(r.root, r.scope)) do
    add(p)
  end
  table.sort(paths)
  local modal = require "utils.modal"
  local lines = {
    { { ("%d file%s this build wrote go to the trash"):format(#paths, #paths == 1 and "" or "s"), modal.hl.file } },
    { { "<leader>Fu brings them back · the documents stay", modal.hl.muted } },
    "",
  }
  for i = 1, math.min(#paths, 8) do
    lines[#lines + 1] = { { "  " .. paths[i], modal.hl.muted } }
  end
  if #paths > 8 then
    lines[#lines + 1] = { { ("  … and %d more"):format(#paths - 8), modal.hl.muted } }
  end
  modal.confirm(lines, { title = "Clean the build", confirm = "Clean", danger = true }, function()
    local ops = require "files.ops"
    for _, p in ipairs(paths) do
      ops.trash(r.root .. "/" .. p)
    end
    -- empty folders the build made are left behind by the trash: remove those that are empty now
    local dirs = {}
    for _, p in ipairs(paths) do
      local d = vim.fs.dirname(p)
      while d and d ~= "." and d ~= "" do
        dirs[d] = true
        d = vim.fs.dirname(d)
      end
    end
    local list = vim.tbl_keys(dirs)
    table.sort(list, function(x, y)
      return #x > #y -- deepest first
    end)
    for _, d in ipairs(list) do
      vim.uv.fs_rmdir(r.root .. "/" .. d)
    end
    os.remove(state.path(r.root, r.scope))
    os.remove(M.manifest_path(r.root, r.scope))
    fresh_run()
    view().code_done(
      "plan.md",
      "# Clean\n\nThe build's files are in the trash. The documents are untouched: ⏎ plans again.\n",
      "cleaned",
      true
    )
    state.feed(
      "step",
      ("%d file%s to the trash, the run forgotten"):format(#paths, #paths == 1 and "" or "s"),
      nil,
      "Clean"
    )
    state.changed()
    log.info(("Build: cleaned · %d file%s in the trash (<leader>Fu)"):format(#paths, #paths == 1 and "" or "s"))
  end)
end

--- `+`/`-`: fix rounds
---@param delta integer
function M.fix_rounds(delta)
  local r = state.run
  if r and not r.running then
    r.max_fixes = math.max(0, math.min(5, r.max_fixes + delta))
    state.changed()
  end
end

-- ── Entry ────────────────────────────────────────────────────────────────────

--- What a layer's (or a task's) pre-flight shows in the code pane: what it builds and from which document
---@param s BuildScope
---@param task BuildTask?
---@return string
local function intro(s, task)
  local what = {
    foundation = "The manifest, the layout, the tooling and a minimal entry point that runs: what the domain and the design are built on. No features yet.",
    domain = "The entities, rules and use cases SPEC.md describes, with their tests, on top of the files the project has. No interface.",
    design = "The theme, styles, components and screens DESIGN.md describes, wired to the domain the project has (or sample data when it has none).",
    feature = "This requirement end to end, on top of the project as it is: the domain it needs, the interface that reaches it, the tests of its acceptance criteria, following the patterns the code already uses.",
    recipe = "This recipe applied to the project as it is, where STACK.md and the existing code put each kind of file.",
  }
  local out = {
    ("# Build · %s"):format(task and task.title or s.label),
    "",
    ("From %s. %s"):format(task and s.name == "feature" and (task.id .. " of SPEC.md") or s.from, what[s.name] or ""),
    "",
  }
  if task then
    vim.list_extend(out, vim.split(vim.trim(task.text), "\n", { plain = true }))
    out[#out + 1] = ""
  end
  out[#out + 1] =
    "⏎ plans it: the review shows every file (and the existing ones it changes) before anything is written."
  return table.concat(out, "\n") .. "\n"
end

---@param a BuildTask?
---@param b BuildTask?
---@return boolean
local function same_task(a, b)
  return (a and a.id) == (b and b.id)
end

--- <leader>aSb…: the build view of this project, for one scope (scope.lua: "all" = the whole project, a layer, or a task
--- scope with its `task`: a requirement, a recipe). A run of that scope (and task) going on is shown as it is; a saved one
--- that can go on is offered to resume; otherwise the pre-flight of a new one.
---@param scope string?
---@param task BuildTask?
function M.open(scope, task)
  local s = scopes.get(type(scope) == "string" and scope or nil)
  local name = s.name ~= "all" and s.name or nil
  local root = require("agent.kit.snapshot").root()
  if
    state.run
    and state.run.root == root
    and state.run.scope == name
    and (task == nil or same_task(state.run.task, task))
  then
    return view().open()
  end
  if state.run and state.run.running then
    return log.warn(
      ("Build: %s is still building (%s shows it, x there stops it)"):format(
        state.run.name,
        scopes.keys(state.run.scope)
      )
    )
  end
  local docs, missing = M.docs(root, s.name)
  if #missing > 0 then
    local how = vim.tbl_map(function(f)
      return ("%s (<leader>aS%s)"):format(f, KEYS[f])
    end, missing)
    local reads = s.name == "all" and "The build reads all four documents."
      or ("The %s build is built from %s."):format(s.label, s.from)
    return log.error("Build: missing " .. table.concat(how, ", ") .. ". " .. reads)
  end
  live.docs, live.written, live.prompts, live.autofixed = docs, nil, {}, {}
  local saved = state.load(root, name)
  if saved and task and not same_task(saved.task, task) then -- one run per task scope: another task starts afresh
    if state.resumable(saved) then
      log.info(
        ("Build: the unfinished %s build is set aside for %s"):format(saved.task and saved.task.id or name, task.id)
      )
    end
    saved = nil
  end
  if state.resumable(saved) then
    state.run = saved
    saved.docs = M.doc_sizes(docs, name)
    saved.outcome = saved.phase == "review" and "■ the plan is waiting · ⏎ builds · n replans"
      or ("■ paused at %s · ⏎ continues · n replans"):format(
        saved.phase == "stopped" and (saved.at or "write") or saved.phase
      )
    M.reestimate()
  elseif vim.tbl_contains(scopes.TASKS, s.name) and not task then
    return log.info(
      ("Build: a %s build needs its %s (%s)"):format(
        s.label,
        s.name == "feature" and "requirement" or "recipe",
        scopes.keys(s.name)
      )
    )
  else
    state.new(root, M.doc_sizes(docs, name), name, task)
  end
  view().open()
  if state.run.plan then -- a run with a plan comes back with it on screen (closing Neovim loses nothing)
    M.show_plan()
  elseif name then
    view().code_done("plan.md", intro(s, state.run.task), state.run.task and state.run.task.id or s.label, true)
  end
end

--- The menu's layers: <leader>aSbb (all), aSbt (foundation, STACK.md), aSbs (domain, SPEC.md), aSbd (design, DESIGN.md)
function M.all()
  M.open "all"
end
function M.foundation()
  M.open "foundation"
end
function M.domain()
  M.open "domain"
end
function M.design()
  M.open "design"
end

--- `P`: the plan, in the code pane (what the build writes against), in any phase
function M.show_plan()
  local r = state.run
  if not r or not r.plan then
    return log.info "Build: no plan yet (⏎ in the pre-flight asks for one)"
  end
  view().code_done("plan.md", M.plan_text(r.plan), "the plan", true)
end

--- Older callers: the whole build
M.run = M.all

--- <leader>aSB: check again (opens the view of the saved run when there is no live one)
function M.check_again()
  local root = require("agent.kit.snapshot").root()
  if not (state.run and state.run.root == root) then
    local saved = state.load(root)
    if not saved or not saved.plan then
      return log.info "Build: no build here yet (<leader>aSbb, or a layer: bt bs bd)"
    end
    state.run = saved
  end
  view().open()
  M.recheck()
end

return M
