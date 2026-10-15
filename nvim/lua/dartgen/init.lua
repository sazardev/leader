-- ── Dart code generation (build_runner) ──────────────────────────────────────
-- `<leader>dg` starts/stops `dart run build_runner watch` for the package of the current file, in the background: the
-- statusline says `gen …` while it builds, `gen` when it is up to date and `gen ✗ N` when it failed, the errors land as
-- diagnostics on the file they point at, and `<leader>dL` shows the whole output. `<leader>dG` builds once. Opening a
-- file whose generated part (`x.g.dart`, `x.freezed.dart`) does not exist says so once. The watch is resident (a Dart
-- VM): in light mode `<leader>dg` builds once instead. Saving an `.arb` file runs `flutter gen-l10n` (packages with
-- l10n.yaml), so new translation keys exist for the LSP at once.
local log = require "utils.log"
local parse = require "dartgen.parse"

local M = {}

local NS = vim.api.nvim_create_namespace "dartgen"
local MAX_LOG = 3000 -- lines of output kept per package

---@class DartgenJob
---@field root string
---@field proc vim.SystemObj?
---@field watch boolean
---@field status string "building" | "ok" | "failed" | "stopped"
---@field parser DartgenState
---@field errors DartgenError[] of the last failed build
---@field failed boolean the last finished build failed (a "fixed" note when the next one passes)
---@field log string[]
---@field files string[] buffers' paths that got diagnostics (cleared on the next good build)

---@type table<string, DartgenJob>
local jobs = {}

--- The package root of a buffer (where pubspec.yaml is)
---@param buf integer?
---@return string?
function M.root(buf)
  return vim.fs.root(buf or 0, "pubspec.yaml")
end

---@param root string
---@return boolean
local function uses_codegen(root)
  local f = io.open(root .. "/pubspec.yaml", "r")
  if not f then
    return false
  end
  local text = f:read "*a"
  f:close()
  return parse.uses_codegen(text)
end

--- The errors of a failed build as diagnostics on their files (open buffers; the others get them when opened)
---@param job DartgenJob
local function place(job)
  for _, path in ipairs(job.files) do
    local buf = vim.fn.bufnr(path)
    if buf > 0 then
      vim.diagnostic.reset(NS, buf)
    end
  end
  job.files = {}
  local by_file = {}
  for _, e in ipairs(job.errors) do
    local path = job.root .. "/" .. e.file
    by_file[path] = by_file[path] or {}
    table.insert(by_file[path], {
      lnum = math.max((e.lnum or 1) - 1, 0),
      col = math.max((e.col or 1) - 1, 0),
      message = e.msg ~= "" and e.msg or "code generation failed",
      source = e.builder,
      severity = vim.diagnostic.severity.ERROR,
    })
  end
  for path, diags in pairs(by_file) do
    job.files[#job.files + 1] = path
    local buf = vim.fn.bufadd(path)
    vim.diagnostic.set(NS, buf, diags)
  end
end

---@param job DartgenJob
---@param line string
local function on_line(job, line)
  job.log[#job.log + 1] = line
  if #job.log > MAX_LOG then
    table.remove(job.log, 1)
  end
  local event = parse.feed(job.parser, line)
  if event == "start" then
    job.status = "building"
  elseif event == "ok" then
    local was_failed = job.failed
    job.status, job.errors, job.failed = "ok", {}, false
    place(job)
    if was_failed then
      log.info "Codegen fixed: build_runner is up to date"
    elseif not job.watch then
      log.info(("Codegen done: %d files written"):format(job.parser.outputs or 0))
    end
  elseif event == "fail" then
    job.status, job.errors, job.failed = "failed", job.parser.errors, true
    place(job)
    local first = job.errors[1]
    log.error(
      ("Codegen failed: %d error%s%s (<leader>dL output)"):format(
        #job.errors,
        #job.errors == 1 and "" or "s",
        first and (" · " .. first.file .. ": " .. first.msg) or ""
      )
    )
  end
end

--- Runs build_runner for a package
---@param root string
---@param watch boolean
local function start(root, watch)
  local job = {
    root = root,
    watch = watch,
    status = "building",
    parser = parse.new(),
    errors = {},
    failed = false,
    log = {},
    files = {},
  }
  jobs[root] = job
  local pending = ""
  local function on_output(_, data)
    if not data then
      return
    end
    vim.schedule(function()
      local text = pending .. data
      local lines = vim.split(text, "\n", { plain = true })
      pending = table.remove(lines)
      for _, line in ipairs(lines) do
        on_line(job, line)
      end
    end)
  end
  local ok, proc = pcall(vim.system, { "dart", "run", "build_runner", watch and "watch" or "build" }, {
    cwd = root,
    stdout = on_output,
    stderr = on_output,
  }, function(out)
    vim.schedule(function()
      if pending ~= "" then
        on_line(job, pending)
      end
      if jobs[root] == job then
        if job.status == "building" then
          job.status = out.code == 0 and "ok" or "failed"
        end
        if job.watch then
          job.status = "stopped"
        end
        job.proc = nil
      end
    end)
  end)
  if not ok then
    jobs[root] = nil
    return log.error("Codegen: could not run dart (" .. tostring(proc) .. ")")
  end
  job.proc = proc
end

---@param job DartgenJob
local function stop(job)
  if job.proc then
    job.proc:kill "sigint" -- build_runner stops cleanly on Ctrl-C (and takes its compiler with it)
  end
  job.status = "stopped"
end

---@return string? root, string? error
local function current_root()
  local root = M.root()
  if not root then
    return nil, "no pubspec.yaml above this file"
  end
  if not uses_codegen(root) then
    return nil, "this package does not use build_runner (not in pubspec.yaml)"
  end
  return root
end

--- Starts or stops the watch of the current package
function M.toggle()
  local root, err = current_root()
  if not root then
    return log.warn("Codegen: " .. err)
  end
  local job = jobs[root]
  if job and job.proc then
    stop(job)
    return log.info "Codegen watch stopped"
  end
  if require("core.light").enabled then
    log.info "Codegen: light mode, building once (a watch keeps a Dart VM resident)"
    return start(root, false)
  end
  start(root, true)
  log.info "Codegen watch started: it rebuilds on every save"
end

--- Builds the current package once
function M.build()
  local root, err = current_root()
  if not root then
    return log.warn("Codegen: " .. err)
  end
  local job = jobs[root]
  if job and job.proc then
    return log.info(job.watch and "Codegen: the watch is already running" or "Codegen: already building")
  end
  start(root, false)
end

--- The output of the current package's build_runner in a scratch window
function M.show_log()
  local job = jobs[M.root() or ""]
  if not job then
    return log.info "Codegen: nothing has run for this package (<leader>dg starts the watch)"
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, job.log)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  vim.cmd "botright split"
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_height(0, math.max(8, math.floor(vim.o.lines * 0.35)))
  vim.cmd "normal! G"
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true })
end

--- Statusline text: "gen …" building, "gen" up to date, "gen ✗ N" failed; "" when nothing runs for this package
---@return string
function M.statusline()
  local job = jobs[M.root() or ""]
  if not job or (job.status == "stopped" and not job.proc) or (not job.watch and job.status == "ok") then
    return ""
  end
  if job.status == "building" then
    return "gen …"
  elseif job.status == "failed" then
    return ("gen ✗ %d"):format(math.max(#job.errors, 1))
  end
  return "gen"
end

---@type table<string, boolean>
local warned = {}

--- Says once per file when a generated part it declares does not exist and no watch would create it
---@param buf integer
function M.check_parts(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" or warned[path] then
    return
  end
  local root = M.root(buf)
  if not root or (jobs[root] and jobs[root].proc) then
    return
  end
  local dir = vim.fs.dirname(path)
  for _, part in ipairs(parse.generated_parts(vim.api.nvim_buf_get_lines(buf, 0, 80, false))) do
    if not vim.uv.fs_stat(dir .. "/" .. part) then
      warned[path] = true
      return log.warn(("Codegen: %s does not exist yet (<leader>dg starts build_runner watch)"):format(part))
    end
  end
end

-- ── translations: `flutter gen-l10n` when an .arb file is saved ──────────────

---@type table<string, vim.SystemObj> running gen-l10n per package (a second save waits for the first)
local l10n_jobs = {}

--- The first line that says what went wrong in gen-l10n's output
---@param text string
---@return string
function M.l10n_error(text)
  for line in text:gmatch "[^\n]+" do
    local l = vim.trim(line)
    if
      l ~= ""
      and not l:match "^Because l10n%.yaml"
      and (l:lower():find "error" or l:find "Exception" or l:find "must")
    then
      return l
    end
  end
  return vim.trim(text):match "[^\n]*$" or "unknown error"
end

--- Regenerates the localizations of the package an .arb file belongs to (the package must have l10n.yaml): the
--- getters the LSP offers (`AppLocalizations.of(context).newKey`) exist as soon as the file is saved
---@param buf integer
function M.l10n(buf)
  local root = vim.fs.root(buf, "l10n.yaml")
  if not root or l10n_jobs[root] then
    return
  end
  local ok, proc = pcall(vim.system, { "flutter", "gen-l10n" }, { cwd = root, text = true }, function(out)
    vim.schedule(function()
      l10n_jobs[root] = nil
      if out.code == 0 then
        log.info "Translations regenerated (flutter gen-l10n)"
      else
        log.error("Translations: " .. M.l10n_error((out.stdout or "") .. "\n" .. (out.stderr or "")))
      end
    end)
  end)
  if ok then
    l10n_jobs[root] = proc
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("Dartgen", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*.arb",
    callback = function(ev)
      M.l10n(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = group,
    pattern = "*.dart",
    callback = function(ev)
      M.check_parts(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      for _, job in pairs(jobs) do
        stop(job)
      end
    end,
  })
end

--- For tests: the job of a package
---@param root string
---@return DartgenJob?
function M.job(root)
  return jobs[root]
end

return M
