-- ── Doctor: a troubleshooting agent ──────────────────────────────────────────
-- The app does not build, does not start, dies at runtime, or something is off before you even compile. You hand the doctor the
-- failure in the way that is easiest (the last terminal, the clipboard, a command it runs, a log file, a selection, your own
-- words, or just "check this project") and it works like an engineer would:
--   1. evidence, free:   colors off, repeated lines folded, secrets blacked out, the stack frames turned into code excerpts,
--                         toolchain versions, what git says changed (evidence.lua, probe.lua)
--   2. known causes:     a table of the usual suspects (missing module, port in use, daemon down, .env keys…) and checks of the
--                         project itself (dependencies, lockfile, .env, toolchain, a merge in progress): shown before any model
--   3. the model, once:  after you see what is sent and say yes; it may ask to read a file, search, or run a read-only command
--                         (tools.lua: an allowlist, no shell, secrets never readable), at most `max_rounds` more times
--   4. steps:            commands (captured, or in the terminal), edits (one proposal with the usual inline diff), manual
--                         things; nothing runs without a yes that shows it; what happened goes back into the next request
--   5. check again:      `r` runs the failing command again (or reads the terminal) and says whether it still fails
-- The screen is utils/market.lua (ui.lua); a case is kept in memory so closing it loses nothing (`reopen`).
local evidence = require "agent.doctor.evidence"
local log = require "utils.log"
local probe = require "agent.doctor.probe"
local prompt = require "agent.doctor.prompt"
local settings = require("core.settings").agent.doctor
local steps = require "agent.doctor.steps"
local tools = require "agent.doctor.tools"
local ui = require "agent.doctor.ui"

local M = {}

---@type table<string, DoctorSession>
local cases = {}
local last_root

---@return string
local function root_of()
  return require("agent.kit.snapshot").root()
end

--- Free findings: the known causes of the output (if that module is there), the checks of the project and of the toolchain
---@param text string
---@param ctx DoctorCtx
---@param versions table<string, string>
---@return DoctorFinding[]
local function free_findings(text, ctx, versions)
  local out, seen, ran = {}, {}, {}
  local function add(list)
    for _, f in ipairs(list or {}) do
      local cmd = f.steps and f.steps[1] and f.steps[1].run
      if not seen[f.id] and not (cmd and ran[cmd]) then -- two findings that end in the same command are one finding
        seen[f.id] = true
        out[#out + 1] = f
        if cmd then
          ran[cmd] = true
        end
      end
    end
  end
  local ok, known = pcall(require, "agent.doctor.known")
  if ok and text ~= "" then
    local found_ok, found = pcall(known.find, text, { has = ctx.has, pm = probe.package_manager(ctx), root = ctx.root })
    add(found_ok and found or {})
  end
  add(probe.checks(ctx))
  add(probe.version_checks(ctx, versions))
  return out
end

---@param s DoctorSession
local function refresh(s)
  if s.market and vim.api.nvim_win_is_valid(s.market.wins.list) then
    require("utils.market").refresh(s.market)
  end
end

--- The evidence a request carries
---@param s DoctorSession
---@param question string?
---@return DoctorEvidence
local function evidence_of(s, question)
  local tried = {}
  vim.list_extend(tried, s.tried or {})
  local all_steps = {}
  for _, f in ipairs(s.free) do
    vim.list_extend(all_steps, f.steps)
  end
  if s.diagnosis then
    vim.list_extend(all_steps, s.diagnosis.steps)
    if question then
      tried[#tried + 1] = ("earlier diagnosis: %s %s"):format(s.diagnosis.summary, s.diagnosis.cause)
    end
  end
  vim.list_extend(tried, steps.describe_tried(all_steps))
  return {
    problem = s.problem,
    source = s.source.label,
    output = s.output,
    code = s.code,
    versions = s.versions,
    changes = s.changes,
    known = s.free,
    tried = tried,
    tool_results = s.tool_results,
    question = question,
  }
end

--- Makes a session from a source: all the free work, then opens the screen. `opts`: root, source, problem?, tried?, rerun?
---@param opts { root: string?, source: table, problem: string?, tried: string[]?, rerun: string? }
function M.start(opts)
  local root = opts.root or root_of()
  local ctx = probe.ctx(root)
  local text = evidence.redact(evidence.clean(opts.source.text or ""))
  local frames = evidence.frames(text, root, function(abs)
    return vim.fn.filereadable(abs) == 1
  end, settings.max_frames)
  local code = {}
  for _, f in ipairs(frames) do
    local excerpt = evidence.code_around(f.file, f.lnum, settings.frame_context)
    if excerpt and tools.readable(root, f.file) then
      code[#code + 1] = { path = f.file:sub(#root + 2), lnum = f.lnum, text = excerpt }
    end
  end
  local versions, changes
  local left = 2
  local function ready()
    left = left - 1
    if left > 0 then
      return
    end
    ---@type DoctorSession
    local s = {
      root = root,
      source = opts.source,
      problem = opts.problem,
      output = evidence.excerpt(text, settings.max_output_chars),
      code = code,
      versions = versions or {},
      changes = changes,
      free = free_findings(text, ctx, versions or {}),
      tool_results = {},
      tried = opts.tried or {},
      rerun = opts.rerun or opts.source.command,
    }
    cases[root], last_root = s, root
    M.show(s)
  end
  probe.versions(ctx, function(v)
    versions = v
    ready()
  end)
  probe.changes(ctx, function(c)
    changes = c
    ready()
  end)
end

--- Opens (or re-opens) the screen of a case
---@param s DoctorSession
function M.show(s)
  s.market = ui.open(s, {
    ask = M.ask,
    act = M.act,
    toggle = M.toggle,
    verify = M.verify,
    followup = M.followup,
    preview = function(session)
      local req = prompt.request(evidence_of(session), tools.DESCRIPTION)
      local lines = { { { "  WHAT IS SENT", require("utils.modal").hl.key } }, { { "" } } }
      for _, l in ipairs(vim.split(req.prompt, "\n", { plain = true })) do
        lines[#lines + 1] = { { "  " .. l:sub(1, 300), require("utils.modal").hl.muted } }
      end
      return lines
    end,
  })
end

--- The case of a project, if there is one (the screen's state; also what the tests look at)
---@param root string?
---@return DoctorSession?
function M.case(root)
  return cases[root or root_of()]
end

--- `<leader>aXr`: the last case of this project
function M.reopen()
  local s = cases[root_of()] or cases[last_root or ""]
  if not s then
    return log.info "Doctor: no case yet (<leader>aXx diagnoses the last terminal or the clipboard)"
  end
  M.show(s)
end

-- ── asking the model ────────────────────────────────────────────────────────

--- A round: one request; if the model asks to look at something, it is shown it and asked again (bounded)
---@param s DoctorSession
---@param question string?
---@param n integer rounds already made
local function round(s, question, n)
  local req = prompt.request(evidence_of(s, question), n < settings.max_rounds and tools.DESCRIPTION or nil)
  req.label = "diagnosing"
  req.preapproved = n > 0 -- the first request was confirmed; the follow-ups of the same case are under the caps
  s.asking = n == 0 and ("waiting for " .. (s.model or "the model")) or ("round %d: reading what it asked for…"):format(n + 1)
  refresh(s)
  require("agent").complete(req, function(ok, text)
    local function done(msg, level)
      s.asking = nil
      refresh(s)
      if msg then
        log[level or "warn"]("Doctor: " .. msg)
      end
    end
    if not ok then
      return done(tostring(text))
    end
    local diagnosis, err = prompt.parse(text)
    if not diagnosis then
      return done(err)
    end
    if #diagnosis.need > 0 and n < settings.max_rounds then
      local left = #diagnosis.need
      for _, call in ipairs(diagnosis.need) do
        tools.call(call, s.root, function(result)
          s.tool_results[#s.tool_results + 1] = { call = prompt.call_label(call), text = result }
          left = left - 1
          s.asking = ("looking at: %s"):format(prompt.call_label(call))
          refresh(s)
          if left == 0 then
            round(s, question, n + 1)
          end
        end)
      end
      return
    end
    s.diagnosis = diagnosis
    done()
    if not (s.market and vim.api.nvim_win_is_valid(s.market.wins.list)) then
      log.info("Doctor: diagnosis ready: " .. (diagnosis.summary ~= "" and diagnosis.summary or "see the steps") .. " (<leader>aXr)")
    end
  end)
end

--- Asks the model (after showing what is sent and how much it is)
---@param s DoctorSession
---@param question string?
function M.ask(s, question)
  if s.asking then
    return log.info "Doctor: already asking"
  end
  local sel = require("agent.selection").current { name = "doctor", tier = "main" }
  if not sel then
    return log.warn "Doctor: no agent backend found (<leader>am)"
  end
  local req = prompt.request(evidence_of(s, question), tools.DESCRIPTION)
  s.model = require("agent.selection").label(sel)
  s.estimate = math.floor((#req.system + #req.prompt) / 4)
  local modal = require "utils.modal"
  local lines = {
    { { ("%s · about %d tokens in"):format(s.model, s.estimate), modal.hl.file } },
    "",
  }
  for _, l in ipairs(ui.sent_summary(s)) do
    lines[#lines + 1] = { { "· " .. l, modal.hl.muted } }
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = { { "Secrets are blacked out first; p in the screen shows the exact text.", modal.hl.muted } }
  modal.confirm(lines, { title = "Diagnose", confirm = "Ask" }, function()
    round(s, question, 0)
  end)
end

--- `a`: a follow-up question about the case
---@param s DoctorSession
function M.followup(s)
  local modal = require "utils.modal"
  modal.input({ { { "What do you want to know or tell it? (what you saw after a step, a doubt, another symptom)", modal.hl.muted } } }, { title = "Ask more", confirm = "Ask" }, function(text)
    if vim.trim(text) ~= "" then
      M.ask(s, vim.trim(text))
    end
  end)
end

-- ── steps ───────────────────────────────────────────────────────────────────

---@param s DoctorSession
---@param step DoctorPlanStep
function M.toggle(_, step)
  step.state = step.state ~= "done" and "done" or nil
end

---@param s DoctorSession
---@param step DoctorPlanStep
---@param how "captured"|"terminal"
function M.act(s, step, how)
  if step.kind == "command" then
    steps.confirm_command(step, how, function()
      if how == "terminal" then
        if s.market then
          require("utils.market").close(s.market)
        end
        steps.run_terminal(s.root, step)
        log.info "Doctor: running in the terminal; <leader>aXr reopens the case and r checks again"
      else
        step.state = nil
        step.output = "running…"
        refresh(s)
        steps.run_captured(s.root, step, function()
          refresh(s)
        end)
      end
    end)
  elseif step.kind == "edit" and s.diagnosis then
    steps.apply_edit(s.root, step, s.diagnosis, function()
      if s.market then
        require("utils.market").close(s.market)
      end
    end)
  else
    M.toggle(s, step)
    refresh(s)
  end
end

-- an edit step is done when its proposal is accepted
require("agent.events").on("proposal.accepted", function(ev)
  local step = ev.job and ev.job.meta and ev.job.meta.doctor_step
  if step then
    step.state = "done"
    log.info "Doctor: edit applied: <leader>aXr reopens the case and r checks again"
  end
end)

-- ── evidence sources ────────────────────────────────────────────────────────

--- Runs a command captured and hands back everything it printed with its exit code
---@param root string
---@param cmd string
---@param cb fun(text: string, code: integer)
local function capture(root, cmd, cb)
  local ok = pcall(vim.system, { vim.o.shell, vim.o.shellcmdflag, cmd }, { cwd = root, text = true, timeout = settings.command_timeout_ms }, function(res)
    vim.schedule(function()
      cb((res.stdout or "") .. "\n" .. (res.stderr or ""), res.signal == 15 and 124 or res.code)
    end)
  end)
  if not ok then
    cb("could not start the shell", 127)
  end
end

--- The text of the last terminal when it looks like it holds errors
---@return string?
local function terminal_text()
  local text = require("agent.errors.source").terminal(settings.terminal_lines)
  if text and require("agent.errors.parse").looks_like_errors(text) then
    return text
  end
end

---@return string?
local function clipboard_text()
  for _, reg in ipairs { "+", '"' } do
    local ok, text = pcall(vim.fn.getreg, reg)
    if ok and text and vim.trim(text) ~= "" then
      return text
    end
  end
end

--- `<leader>aXx`: the best evidence at hand (the last terminal, the quickfix list, the clipboard), else asks you to describe it
function M.auto()
  local root = root_of()
  local text = terminal_text()
  if text then
    return M.start { root = root, source = { label = "the last terminal", kind = "terminal", text = text } }
  end
  local errors = require("agent.errors.parse").from_quickfix { root = root }
  if #errors > 0 then
    local lines = vim.tbl_map(function(e)
      return ("%s:%d:%d: %s"):format(e.file, e.lnum, e.col or 1, e.text)
    end, errors)
    return M.start { root = root, source = { label = "the quickfix list", kind = "quickfix", text = table.concat(lines, "\n") } }
  end
  local clip = clipboard_text()
  if clip and require("agent.errors.parse").looks_like_errors(clip) then
    return M.start { root = root, source = { label = "the clipboard", kind = "clipboard", text = clip } }
  end
  log.info "Doctor: no error in the last terminal, the quickfix list or the clipboard: describe it, or run a command"
  M.describe()
end

--- `<leader>aXp`: what is in the clipboard (copy the error, press this)
function M.paste()
  local clip = clipboard_text()
  if not clip then
    return log.info "Doctor: the clipboard is empty"
  end
  M.start { source = { label = "the clipboard", kind = "clipboard", text = clip } }
end

--- `<leader>aXd`: in your own words; the last terminal rides along when it looks like errors
function M.describe()
  local attached = terminal_text()
  require("agent.kit.draft").open({
    id = "doctor",
    title = "Describe the problem",
    hint = {
      "What fails, when it started, what you changed, what you expected. Paste an error if you have one.",
      attached and "The last terminal's output is attached." or "No error in the last terminal: only your words (and the project's state) are used.",
    },
  }, function(text)
    require("agent.kit.draft").forget "doctor"
    M.start { problem = text, source = { label = attached and "your words + the last terminal" or "your words", kind = "described", text = attached or "" } }
  end)
end

--- `<leader>aXs` (visual): the selected lines
function M.selection()
  local a, b = vim.fn.line "v", vim.fn.line "."
  vim.api.nvim_feedkeys(vim.keycode "<Esc>", "nx", false)
  local lines = vim.api.nvim_buf_get_lines(0, math.min(a, b) - 1, math.max(a, b), false)
  if #lines == 0 then
    return
  end
  M.start { source = { label = "the selection", kind = "selection", text = table.concat(lines, "\n") } }
end

--- Diagnoses a command's output (it runs it first, captured)
---@param cmd string
function M.run_command(cmd)
  local root = root_of()
  log.info(("Doctor: running `%s`…"):format(cmd))
  capture(root, cmd, function(text, code)
    if code == 0 and not require("agent.errors.parse").looks_like_errors(text) then
      return log.info(("Doctor: `%s` passes (exit 0, no error in its output)"):format(cmd))
    end
    M.start {
      root = root,
      source = { label = ("`%s` (exit %d)"):format(cmd, code), kind = "command", text = text, command = cmd },
      rerun = cmd,
    }
  end)
end

--- `<leader>aXc`: the project's own commands (build, test, run), docker logs, or one you type
function M.command()
  local root = root_of()
  local snapshot = require "agent.kit.snapshot"
  local items = {}
  for _, c in ipairs(snapshot.commands(snapshot.collect(root))) do
    items[#items + 1] = { label = c.label, desc = c.cmd, value = c.cmd }
  end
  if vim.uv.fs_stat(root .. "/docker-compose.yml") or vim.uv.fs_stat(root .. "/compose.yaml") or vim.uv.fs_stat(root .. "/compose.yml") or vim.uv.fs_stat(root .. "/docker-compose.yaml") then
    items[#items + 1] = { label = "docker compose logs", desc = "the services' last 200 lines", value = "docker compose logs --tail 200" }
  end
  items[#items + 1] = { label = "another command…", desc = "type it", value = false }
  require("tasks.picker").choose(items, { title = "Run and diagnose" }, function(cmd)
    if cmd then
      return M.run_command(cmd)
    end
    local modal = require "utils.modal"
    modal.input({ { { "Command to run in the project and diagnose:", modal.hl.muted } } }, { title = "Run and diagnose", confirm = "Run" }, function(text)
      if vim.trim(text) ~= "" then
        M.run_command(vim.trim(text))
      end
    end)
  end)
end

--- `<leader>aXl`: the end of a log file of the project (or a path you give)
function M.log()
  local root = root_of()
  local found = vim.fs.find(function(name)
    return name:match "%.log$" ~= nil
  end, { path = root, type = "file", limit = 40 })
  local items = {}
  for _, f in ipairs(found) do
    if not f:find("/node_modules/", 1, true) and not f:find("/.git/", 1, true) then
      items[#items + 1] = { label = f:sub(#root + 2), value = f }
    end
  end
  local function read(path)
    local ok, lines = pcall(vim.fn.readfile, path)
    if not ok then
      return log.warn("Doctor: cannot read " .. path)
    end
    local tail = vim.list_slice(lines, math.max(1, #lines - settings.terminal_lines + 1), #lines)
    M.start { root = root, source = { label = vim.fn.fnamemodify(path, ":t"), kind = "log", text = table.concat(tail, "\n") } }
  end
  items[#items + 1] = { label = "another file…", desc = "type its path", value = false }
  require("tasks.picker").choose(items, { title = "Log file" }, function(path)
    if path then
      return read(path)
    end
    local modal = require "utils.modal"
    modal.input({ { { "Path of the log file:", modal.hl.muted } } }, { title = "Log file", confirm = "Read" }, function(text)
      local p = vim.fn.expand(vim.trim(text))
      if p ~= "" then
        read(p)
      end
    end)
  end)
end

--- `<leader>aXh`: before compiling: the errors the language servers already see in the project, plus every free check
function M.health()
  local root = root_of()
  local lines = {}
  for _, d in ipairs(vim.diagnostic.get(nil, { severity = vim.diagnostic.severity.ERROR })) do
    local name = vim.api.nvim_buf_get_name(d.bufnr)
    if name ~= "" and name:sub(1, #root) == root and #lines < 40 then
      lines[#lines + 1] = ("%s:%d:%d: %s"):format(name, d.lnum + 1, (d.col or 0) + 1, (d.message or ""):gsub("\n.*", ""))
    end
  end
  M.start { root = root, source = { label = "the project's health", kind = "health", text = table.concat(lines, "\n") } }
end

--- `r`: runs the failing command again (or reads the terminal) and says if it still fails; if it does, a new case carries what was tried
---@param s DoctorSession
function M.verify(s)
  local tried = {}
  vim.list_extend(tried, s.tried or {})
  local all_steps = {}
  for _, f in ipairs(s.free) do
    vim.list_extend(all_steps, f.steps)
  end
  if s.diagnosis then
    vim.list_extend(all_steps, s.diagnosis.steps)
  end
  vim.list_extend(tried, steps.describe_tried(all_steps))
  local function again(text, code, label)
    local looks = require("agent.errors.parse").looks_like_errors(text)
    if (code == nil or code == 0) and not looks then
      s.solved = true
      refresh(s)
      return log.info "Doctor: it runs now: nothing failed this time"
    end
    if s.market then
      require("utils.market").close(s.market)
    end
    M.start {
      root = s.root,
      source = { label = label, kind = s.source.kind, text = text, command = s.rerun },
      problem = s.problem,
      tried = tried,
      rerun = s.rerun,
    }
  end
  if s.rerun then
    log.info(("Doctor: running `%s` again…"):format(s.rerun))
    return capture(s.root, s.rerun, function(text, code)
      again(text, code, ("`%s` again (exit %d)"):format(s.rerun, code))
    end)
  end
  local text = terminal_text()
  if not text then
    s.solved = true
    refresh(s)
    return log.info "Doctor: the last terminal shows no error now (run the failing command there first if you have not)"
  end
  again(text, 1, "the last terminal, again")
end

return M
