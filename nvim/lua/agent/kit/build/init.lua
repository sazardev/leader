-- ── Build with agent (<leader>aSb) ───────────────────────────────────────────
-- The project from its four documents (AGENTS.md, STACK.md, DESIGN.md, SPEC.md: it says which is missing and its key), in
-- phases you can watch and steer from the build tab (build/view.lua):
--   ready   pre-flight: the documents, the model of each phase (plan · files · fixes, main or light tier), fix rounds
--   plan    one request: the ordered files, their documents and the earlier files they use (plan.lua)
--   review  the plan with what each file will cost; skip files, change models; Enter starts (this IS the confirmation)
--   write   one small request per file (prompt.lua: documents + plan in the cached system prompt, the API of what exists)
--   check   the manifest's own tools (verify.lua), never commands from the model; gofmt fixes itself
--   fix     the files the errors name, with their errors, `max_fixes` rounds; then check again
-- The run lives in build/state.lua, not in the window: closing the tab (q) leaves it running, the statusline shows it,
-- <leader>aSb brings the view back, `x` stops it. It is saved after every step: a build cut short (Neovim closed) resumes.
-- Every request goes through the spend guard (no question per file once the review is accepted; the caps still apply)
-- and lands in the history (<leader>ah: kit_build_plan, kit_build_file, kit_build_fix).
local compose = require "agent.kit.compose"
local log = require "utils.log"
local plan_mod = require "agent.kit.build.plan"
local prompt = require "agent.kit.build.prompt"
local state = require "agent.kit.build.state"
local verify = require "agent.kit.build.verify"

local M = {}

local KEYS = { ["AGENTS.md"] = "a", ["STACK.md"] = "t", ["DESIGN.md"] = "d", ["SPEC.md"] = "s" }

--- What is running now: the request's process (to stop it) and when this stretch of running began
local live = { handle = nil, since = nil, docs = nil, written = nil, prompts = {}, autofixed = {} }

---@return BuildRun
local function run()
  return state.run --[[@as BuildRun]]
end

---@return table
local function view()
  return require "agent.kit.build.view"
end

-- ── Documents, manifest, estimates ───────────────────────────────────────────

--- The four documents at the root: their text by id, and the files missing
---@param root string
---@return table<string, string>, string[]
function M.docs(root)
  local docs, missing = {}, {}
  for _, d in ipairs(compose.DOCS) do
    local text = require("utils.project").read(root .. "/" .. d.file)
    if text and vim.trim(text) ~= "" then
      docs[d.id] = text
    else
      missing[#missing + 1] = d.file
    end
  end
  return docs, missing
end

---@param docs table<string, string>
---@return { file: string, chars: integer }[]
function M.doc_sizes(docs)
  return vim.tbl_map(function(d)
    return { file = d.file, chars = #(docs[d.id] or "") }
  end, compose.DOCS)
end

--- Where the list of files the last build of `root` wrote is kept (state dir, not the repository)
---@param root string
---@return string
function M.manifest_path(root)
  return vim.fn.stdpath "state" .. "/agent-build/" .. vim.fn.sha256(root):sub(1, 16) .. ".json"
end

---@param root string
---@return string[]
function M.previous(root)
  local text = require("utils.project").read(M.manifest_path(root))
  local ok, list = pcall(vim.json.decode, text or "")
  return ok and type(list) == "table" and list or {}
end

---@param root string
---@param paths string[]
local function remember(root, paths)
  local path = M.manifest_path(root)
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
    chars = chars + #f.path + #f.purpose + 6
  end
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

local ACTION = { plan = "kit_build_plan", files = "kit_build_file", fixes = "kit_build_fix" }

--- "claude/haiku" for a phase, from its tier (main/light) and what <leader>am chose for that tier
---@param phase "plan"|"files"|"fixes"
---@return string label, table? sel
function M.model(phase)
  local sel = require("agent.selection").current { name = ACTION[phase], tier = run().tiers[phase] }
  return sel and require("agent.selection").label(sel) or "no backend", sel
end

--- Dollars per input token of a phase's model, from the history (nil until the model has a price)
---@param phase "plan"|"files"|"fixes"
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
---@param phase "plan"|"files"|"fixes"
function M.cycle(phase)
  local r = state.run
  if not r or r.running then
    return
  end
  r.tiers[phase] = r.tiers[phase] == "main" and "light" or "main"
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
  state.save()
  state.changed()
  local msg = ("Build %s: %s · $%.3f · %dm%02ds"):format(
    r.name,
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
---@param phase "plan"|"files"|"fixes"
---@param on_text fun(delta: string)?
---@param cb fun(ok: boolean, text: string, usage: table?, ms: integer)
local function call(req, phase, on_text, cb)
  local t0 = vim.uv.hrtime()
  req.tier = run().tiers[phase]
  req.on_text = on_text
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

--- The texts written so far (read from disk for what an earlier session wrote)
---@return table<string, string>
local function written()
  if live.written then
    return live.written
  end
  live.written = {}
  for _, f in ipairs(run().files) do
    if f.state == "done" or f.state == "fixed" then
      live.written[f.path] = require("utils.project").read(run().root .. "/" .. f.path)
    end
  end
  return live.written
end

--- The last request sent for a file (what `p` shows in the view)
---@param path string
---@return { system: string, prompt: string }?
function M.sent(path)
  return live.prompts[path]
end

local check -- forward

-- fix: the files the errors name, one after the other, then check again
---@param blamed table<string, string[]>
local function fix(blamed)
  local r = run()
  r.fix_round = r.fix_round + 1
  r.phase = "fix"
  local paths = vim.tbl_keys(blamed)
  table.sort(paths)
  state.feed(
    "step",
    ("round %d · %d file%s"):format(r.fix_round, #paths, #paths == 1 and "" or "s"),
    M.model "fixes",
    "Fix"
  )
  local i = 0
  local function next_fix()
    i = i + 1
    local path = paths[i]
    if not r.running then
      return
    end
    if not path then
      return check()
    end
    local file = state.file(path)
    local req =
      prompt.fix(path, written()[path] or "", table.concat(blamed[path], "\n"), file, r.plan, live.docs, written())
    live.prompts[path] = { system = req.system, prompt = req.prompt }
    r.current = path
    if file then
      file.state = "writing"
    end
    local lines = #blamed[path]
    state.feed(
      "in",
      path,
      ("%d error line%s · %s chars"):format(lines, lines == 1 and "" or "s", size(#req.system + #req.prompt))
    )
    view().code_start(path, "fixing")
    call(req, "fixes", view().code_stream, function(ok, text, usage, ms)
      if not ok then
        if file then
          file.state = "failed"
        end
        return finish("failed", "✗ the fix of " .. path .. " failed", "fail", text)
      end
      local content = prompt.content(text)
      local done, why = write_file(r.root, path, content)
      if not done then
        return finish("failed", "✗ could not write " .. path, "fail", tostring(why))
      end
      written()[path] = content
      if file then
        file.state, file.lines = "fixed", select(2, content:gsub("\n", ""))
        file.cost = (file.cost or 0) + (usage and usage.cost or 0)
      end
      view().code_done(path, content, "fixed")
      state.feed("out", path, usage_text(usage, ms))
      state.save()
      next_fix()
    end)
  end
  next_fix()
end

-- check: the manifest's own tools
check = function()
  local r = run()
  r.phase, r.current = "check", nil
  local checks = verify.checks(r.root, verify.package_manager_hint(live.docs and live.docs.stack))
  if #checks == 0 then
    return finish("done", ("■ %d files written · no checks for this kind of project"):format(#r.files))
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
      remember(
        r.root,
        vim.tbl_map(function(f)
          return f.path
        end, r.files)
      )
      local done = state.progress()
      return finish(
        "done",
        ("✓ built · %d files · checks pass"):format(done),
        "info",
        "every check passes · ⏎ opens a file"
      )
    end
    if failed and failed.autofix and not live.autofixed[failed.label] then -- gofmt: no model, once
      live.autofixed[failed.label] = true
      vim.system(failed.autofix, { cwd = r.root }):wait()
      state.feed("info", table.concat(failed.autofix, " ") .. " · formatting, 0 tokens")
      return check()
    end
    state.feed("fail", failed and failed.label or "check", (output or ""):sub(1, 1200))
    if (output or ""):find "%.golden: no such file" then -- snapshot tests make their golden files, not a model
      return finish(
        "done",
        "■ built · golden files to create",
        "info",
        "snapshot tests need their golden files once: run them with the update flag (teatest: go test ./... -update), then r"
      )
    end
    local planned = vim.tbl_map(function(f)
      return f.path
    end, r.files)
    local outside = verify.outside(output or "", planned)
    if #outside > 0 then
      state.feed("info", "errors in files this build did not write: " .. table.concat(outside, ", "))
    end
    local blamed = verify.blame(output or "", planned)
    local manifest = next(blamed) == nil and verify.manifest_of(planned)
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
    if next(blamed) == nil then
      return finish(
        "failed",
        "✗ " .. (failed and failed.label or "a check") .. " failed",
        "fail",
        "no planned file is named: fix it by hand or ask the agent"
      )
    end
    if r.fix_round >= r.max_fixes then
      return finish("failed", ("✗ still failing after %d fix rounds"):format(r.fix_round), "fail")
    end
    fix(blamed)
  end)
end

-- write: one file at a time, skipping what is done (a resumed run) or skipped
local function write()
  local r = run()
  r.phase = "write"
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
    call(req, "files", view().code_stream, function(ok, text, usage, ms)
      if not ok then
        file.state = "failed"
        return finish(
          "stopped",
          "✗ " .. file.path .. " failed",
          "fail",
          tostring(text) .. " · Enter resumes from this file"
        )
      end
      local content = prompt.content(text)
      local done, why = write_file(r.root, file.path, content)
      if not done then
        file.state = "failed"
        return finish("stopped", "✗ could not write " .. file.path, "fail", tostring(why))
      end
      written()[file.path] = content
      local u = usage or {}
      file.state, file.lines = "done", select(2, content:gsub("\n", ""))
      file.tokens_in, file.tokens_out, file.cached, file.cost, file.ms =
        u.tokens_in, u.tokens_out, u.cache_read, u.cost, ms
      file.model = M.model "files"
      view().code_done(file.path, content)
      state.feed("out", ("%s · %d lines"):format(file.path, file.lines), usage_text(usage, ms))
      state.save()
      next_file()
    end)
  end
  next_file()
end

-- plan: one request
local function plan()
  local r = run()
  r.phase = "plan"
  begin()
  local req = plan_mod.request(live.docs)
  live.prompts["plan.json"] = { system = req.system, prompt = req.prompt }
  state.feed("step", "the documents become a list of files", M.model "plan", "Plan")
  state.feed("in", "plan", ("agents stack design spec · %s chars"):format(size(#req.system + #req.prompt)))
  view().code_start("plan.json", "planning")
  call(req, "plan", view().code_stream, function(ok, text, usage, ms)
    if not ok then
      return finish("ready", "✗ the plan failed", "fail", text)
    end
    local parsed, why = plan_mod.parse(text)
    if not parsed then
      return finish("ready", "✗ the plan failed", "fail", why)
    end
    r.plan = parsed
    r.files = vim.tbl_map(function(f)
      return vim.tbl_extend("force", f, { state = "pending" })
    end, parsed.files)
    r.stale = M.stale(r.root, M.previous(r.root), parsed)
    r.replaced = #vim.tbl_filter(function(f)
      return vim.uv.fs_stat(r.root .. "/" .. f.path) ~= nil
    end, parsed.files)
    state.feed("out", ("plan · %d files"):format(#parsed.files), usage_text(usage, ms))
    view().code_done("plan.md", M.plan_text(parsed), "planned")
    M.reestimate()
    pause()
    r.phase = "review"
    state.save()
    state.changed()
  end)
end

--- The plan as the code pane shows it: one block per file (what it holds, its documents, what it uses)
---@param plan BuildPlan
---@return string
function M.plan_text(plan)
  local out = { "# Plan · " .. plan.name, "" }
  for i, f in ipairs(plan.files) do
    out[#out + 1] = ("%d. `%s`  %s"):format(i, f.path, f.purpose)
    local meta = "   " .. table.concat(f.docs, " ")
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
  live.docs = live.docs or M.docs(r.root)
  r.outcome = nil
  if r.phase == "ready" or not r.plan then
    return plan()
  end
  if r.phase == "review" then
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
    remember(
      r.root,
      vim.tbl_map(function(f)
        return f.path
      end, r.files)
    )
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
  begin()
  check()
end

--- `r`: the checks (and fix rounds) again on the files as they are now
function M.recheck()
  local r = state.run
  if not r or r.running or not r.plan then
    return log.info "Build: nothing to check (the build has no plan yet)"
  end
  live.docs = live.docs or M.docs(r.root)
  live.written = nil
  r.fix_round, live.autofixed, r.outcome = 0, {}, nil
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

--- `n`: a new plan from the documents (the saved run is forgotten)
function M.restart()
  local r = state.run
  if not r or r.running then
    return
  end
  local docs = M.docs(r.root)
  live.docs, live.written, live.prompts, live.autofixed = docs, nil, {}, {}
  local tiers, max = r.tiers, r.max_fixes
  local fresh = state.new(r.root, M.doc_sizes(docs))
  fresh.tiers, fresh.max_fixes = tiers, max
  state.changed()
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

--- <leader>aSb: the build view of this project. A run going on is shown as it is; a saved one that can go on is offered
--- to resume; otherwise the pre-flight of a new one.
function M.open()
  local root = require("agent.kit.snapshot").root()
  if state.run and state.run.root == root then
    return view().open()
  end
  if state.run and state.run.running then
    return log.warn(("Build: %s is still building (x in its view stops it)"):format(state.run.name))
  end
  local docs, missing = M.docs(root)
  if #missing > 0 then
    local how = vim.tbl_map(function(f)
      return ("%s (<leader>aS%s)"):format(f, KEYS[f])
    end, missing)
    return log.error("Build: missing " .. table.concat(how, ", ") .. ". The build reads all four documents.")
  end
  live.docs, live.written, live.prompts, live.autofixed = docs, nil, {}, {}
  local saved = state.load(root)
  if state.resumable(saved) then
    state.run = saved
    saved.docs = M.doc_sizes(docs)
    saved.outcome = ("■ paused at %s · ⏎ continues · n replans"):format(saved.at or saved.phase)
    M.reestimate()
  else
    state.new(root, M.doc_sizes(docs))
  end
  view().open()
end

--- The menu's `b` and older callers
M.run = M.open

--- <leader>aSB: check again (opens the view of the saved run when there is no live one)
function M.check_again()
  local root = require("agent.kit.snapshot").root()
  if not (state.run and state.run.root == root) then
    local saved = state.load(root)
    if not saved or not saved.plan then
      return log.info "Build: no build here yet (<leader>aSb)"
    end
    state.run = saved
  end
  view().open()
  M.recheck()
end

return M
