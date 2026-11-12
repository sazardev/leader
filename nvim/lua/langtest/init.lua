-- ── Tests inside the editor, any language ────────────────────────────────────
-- The same keys in every language menu: `m` the test (or group) under the cursor, `M` the file, `A` the whole
-- project, `.` the last run again, `T` jumps between a file and its test, `O` shows the runner's output. One adapter per
-- runner (adapters/: pytest, vitest/jest/bun, cargo, dotnet, swift) says which tests a buffer defines (treesitter), how to run
-- a scope and how to read its report; this module runs it (one process, no resident server) and paints the result the
-- way the Dart tests do: a mark per test line (✓ passed, ✗ failed, ○ skipped, … running), a failure as a diagnostic on
-- the line that failed with the runner's message, the failures in the quickfix list, one note with the totals. Results
-- are kept per file: a test file opened later shows its marks. Dart keeps its own (darttest/: a streaming reporter).
local log = require "utils.log"
local ts = require "langtest.ts"

local M = {}

M.ADAPTERS = { "pytest", "jsunit", "cargo", "dotnet", "swift", "go" }

local NS = vim.api.nvim_create_namespace "langtest"
local MARKS = vim.api.nvim_create_namespace "langtest.marks"
local SIGN = { pass = "✓", fail = "✗", skip = "○", running = "…" }
local HL = { pass = "LangTestPass", fail = "LangTestFail", skip = "LangTestSkip", running = "LangTestRunning" }

---@class LangTestCtx
---@field scope "nearest"|"file"|"all"
---@field root string
---@field file string      absolute
---@field rel string       relative to the root
---@field test LangTestDef?
---@field tests LangTestDef[]
---@field flags string[]?  extra runner flags (Go's -race/-cover)
---@field report string    where the runner writes its report

---@class LangTestOutput
---@field stdout string
---@field stderr string
---@field report string?
---@field code integer

---@class LangTestResult
---@field id string
---@field name string
---@field status "pass"|"fail"|"skip"
---@field file string?
---@field line integer?
---@field fail_line integer?
---@field message string?
---@field detail string?

---@type table<string, table<string, LangTestResult>> per test file: id → its last result
local results = {}
---@type table<string, string> per test file: ids running now ("…")
local running = {}
local last ---@type { scope: string, file: string, flags: string[]? }?
local last_run ---@type { root: string, list: LangTestResult[], secs: number }?
local output ---@type string[]?
local current ---@type vim.SystemObj?
local current_root ---@type string?
local watching = false

--- The adapter of a buffer's filetype, and the project root it runs in
---@param buf integer
---@return table? adapter, string? root
function M.adapter(buf)
  local ft = vim.bo[buf].filetype
  local file = vim.api.nvim_buf_get_name(buf)
  for _, name in ipairs(M.ADAPTERS) do
    local a = require("langtest.adapters." .. name)
    if vim.tbl_contains(a.filetypes, ft) then
      return a, file ~= "" and a.root(file) or nil
    end
  end
end

--- The result a test definition has (by id, else by its own name when that is unique in the file's results)
---@param by table<string, LangTestResult>
---@param def LangTestDef
---@return LangTestResult?
function M.match(by, def)
  if by[def.id] then
    return by[def.id]
  end
  local found
  for id, r in pairs(by) do
    if r.name == def.name or vim.endswith(id, "::" .. def.name) or vim.endswith(id, " > " .. def.name) then
      if found then
        return nil -- two results of that name: not this one for sure
      end
      found = r
    end
  end
  return found
end

--- Repaints the marks and diagnostics of a file from its stored results
---@param file string
function M.render(file)
  local buf = vim.fn.bufnr(file)
  if buf < 0 or not vim.api.nvim_buf_is_loaded(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, MARKS, 0, -1)
  local adapter = M.adapter(buf)
  if not adapter then
    return
  end
  local by = results[file] or {}
  local count = vim.api.nvim_buf_line_count(buf)
  local diags = {}
  for _, def in ipairs(adapter.tests(buf)) do
    local status = running[file] and running[file][def.id] and "running"
    local r = not status and M.match(by, def)
    status = status or (r and r.status)
    if status and def.line <= count then
      vim.api.nvim_buf_set_extmark(buf, MARKS, def.line - 1, 0, {
        sign_text = SIGN[status],
        sign_hl_group = HL[status],
        priority = 20,
      })
    end
    if r and r.status == "fail" and def.kind == "test" then
      local here = (not r.file or r.file == file) and r.fail_line or nil
      local lnum = math.min(math.max(here or def.line, 1), count)
      diags[#diags + 1] = {
        lnum = lnum - 1,
        col = 0,
        severity = vim.diagnostic.severity.ERROR,
        source = adapter.name,
        message = ("%s: %s"):format(def.name, r.message or "failed"),
      }
    end
  end
  vim.diagnostic.set(NS, buf, diags)
end

--- Results stored per file (a run of the whole project fills many files)
---@param list LangTestResult[]
---@param ctx LangTestCtx
local function store(list, ctx)
  if ctx.scope ~= "all" then
    results[ctx.file] = results[ctx.file] or {}
  end
  for _, r in ipairs(list) do
    local file = r.file or ctx.file
    results[file] = results[file] or {}
    results[file][r.id] = r
  end
end

--- The failures, in the quickfix list (title "Tests"); the list is left alone when nothing failed
---@param list LangTestResult[]
---@param ctx LangTestCtx
local function quickfix(list, ctx)
  local items = {}
  for _, r in ipairs(list) do
    if r.status == "fail" then
      items[#items + 1] = {
        filename = r.file or ctx.file,
        lnum = r.fail_line or r.line or 1,
        text = ("%s: %s"):format(r.id, r.message or "failed"),
        type = "E",
      }
    end
  end
  if #items > 0 then
    vim.fn.setqflist({}, " ", { title = "Tests", items = items })
  end
end

--- The totals of a run (pure)
---@param list LangTestResult[]
---@return { pass: integer, fail: integer, skip: integer }
function M.counts(list)
  local n = { pass = 0, fail = 0, skip = 0 }
  for _, r in ipairs(list) do
    n[r.status] = (n[r.status] or 0) + 1
  end
  return n
end

--- One line with the totals (pure)
---@param list LangTestResult[]
---@param secs number
---@return string, boolean failed
function M.summary(list, secs)
  local n = M.counts(list)
  local parts = { ("%d passed"):format(n.pass) }
  if n.fail > 0 then
    parts[#parts + 1] = ("%d failed"):format(n.fail)
  end
  if n.skip > 0 then
    parts[#parts + 1] = ("%d skipped"):format(n.skip)
  end
  return ("Tests: %s · %.1fs"):format(table.concat(parts, ", "), secs), n.fail > 0
end

--- Is the current buffer (or the working folder, for a scratch buffer) inside a project root?
---@param root string
---@return boolean
local function same_project(root)
  local adapter, current_root = M.adapter(0)
  if adapter and current_root then
    return current_root == root
  end
  local file = vim.api.nvim_buf_get_name(0)
  if file ~= "" and file:sub(1, 1) == "/" then
    return file == root or file:sub(1, #root + 1) == root .. "/"
  end
  local cwd = vim.uv.cwd() or ""
  return cwd == root or cwd:sub(1, #root + 1) == root .. "/"
end

--- The statusline chip: "test ✓12 ✗1" for the last run of THIS project; "" when there is nothing to say.
--- It survives the run (the terminal used to scroll away): a failing test stays red until the next run passes.
---@return string
function M.statusline()
  if current then
    return current_root and same_project(current_root) and "test …" or ""
  end
  local run = last_run
  if not run or not same_project(run.root) then
    return ""
  end
  local n = M.counts(run.list)
  if n.pass + n.fail + n.skip == 0 then
    return ""
  end
  local parts = { "test" }
  if n.pass > 0 then
    parts[#parts + 1] = "✓" .. n.pass
  end
  if n.fail > 0 then
    parts[#parts + 1] = "✗" .. n.fail
  end
  if n.skip > 0 then
    parts[#parts + 1] = "○" .. n.skip
  end
  return table.concat(parts, " ")
end

--- Did the last run of the current project see failures? (the chip turns red)
---@return boolean
function M.failing()
  if current or not last_run then
    return false
  end
  return same_project(last_run.root) and M.counts(last_run.list).fail > 0
end

local function watch()
  if watching then
    return
  end
  watching = true
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = vim.api.nvim_create_augroup("LangTest", { clear = true }),
    callback = function(ev)
      local file = vim.api.nvim_buf_get_name(ev.buf)
      if results[file] then
        vim.schedule(function()
          M.render(file)
        end)
      end
    end,
  })
end

--- Runs a scope from the current buffer: "nearest" | "file" | "all"
---@param scope "nearest"|"file"|"all"
---@param file string? the test file (default: the current buffer's, or its test when it is not one)
---@param opts { flags?: string[] }? extra runner flags (Go's -race/-cover)
function M.run(scope, file, opts)
  local buf = vim.api.nvim_get_current_buf()
  local adapter, root = M.adapter(buf)
  if not adapter then
    return log.info "Tests: no test runner for this filetype"
  end
  if not root then
    return log.warn("Tests: no project around this file (" .. adapter.name .. ")")
  end
  if not adapter.detect(root) then
    return log.warn("Tests: " .. (adapter.missing or "no test runner in package.json (vitest, jest, or a bun project)"))
  end
  if current then
    return log.info "Tests: a run is still going (it ends on its own; the output is in O)"
  end
  file = file or vim.api.nvim_buf_get_name(buf)
  local defs = vim.fn.bufnr(file) == buf and adapter.tests(buf) or {}
  local test
  if scope == "nearest" then
    test = ts.nearest(defs, vim.api.nvim_win_get_cursor(0)[1])
    if not test then
      if #defs == 0 and adapter.alternate and not adapter.is_test(file) then
        local alt = adapter.alternate(file, root)
        if alt and vim.uv.fs_stat(alt) then
          log.info("Tests: running " .. vim.fs.basename(alt) .. ", the test of this file")
          return M.run("file", alt)
        end
      end
      scope = "file"
    end
  end
  local ctx = {
    scope = scope,
    root = root,
    file = file,
    rel = file:sub(1, #root + 1) == root .. "/" and file:sub(#root + 2) or file,
    test = test,
    tests = defs,
    flags = opts and opts.flags,
    report = vim.fn.tempname() .. ".report",
  }
  local cmd = adapter.command(ctx)
  last = { scope = scope, file = file, flags = opts and opts.flags }
  running[file] = {}
  for _, d in ipairs(defs) do
    if scope ~= "nearest" or d.id == test.id or vim.startswith(d.id, test.id) then
      running[file][d.id] = true
    end
  end
  M.render(file)
  watch()
  log.info(("Tests: %s%s"):format(table.concat(cmd, " "):sub(1, 140), test and (" · " .. test.name) or ""))
  local t0 = vim.uv.hrtime()
  local timeout = (require("core.settings").tests or {}).timeout_ms or 600000
  local ok, proc = pcall(vim.system, cmd, { cwd = root, text = true, timeout = timeout }, function(res)
    vim.schedule(function()
      current, current_root = nil, nil
      running[file] = nil
      local report = require("utils.project").read(ctx.report)
      os.remove(ctx.report)
      local result = { stdout = res.stdout or "", stderr = res.stderr or "", report = report, code = res.code }
      output = adapter.display and adapter.display(result)
        or vim.split(((res.stdout or "") .. "\n" .. (res.stderr or "")), "\n", { plain = true })
      local list = adapter.parse(result, ctx)
      local secs = (vim.uv.hrtime() - t0) / 1e9
      last_run = { root = root, list = list, secs = secs }
      store(list, ctx)
      for f in pairs(results) do
        M.render(f)
      end
      M.render(file)
      quickfix(list, ctx)
      if #list == 0 then
        local first = vim.trim(res.stderr or ""):match "[^\n]+" or vim.trim(res.stdout or ""):match "[^\n]+" or ""
        return log.warn(("Tests: no results (exit %d) %s · O shows the output"):format(res.code, first))
      end
      local text, failed = M.summary(list, secs)
      if failed then
        log.warn(text .. " · failures in the quickfix list")
      else
        log.info(text)
      end
    end)
  end)
  if not ok then
    running[file] = nil
    current_root = nil
    last_run = nil
    M.render(file)
    return log.warn("Tests: " .. cmd[1] .. " is not installed")
  end
  current, current_root = proc, root
end

--- `.`: the last run again (from its file, wherever the cursor is)
function M.again()
  if not last then
    return log.info "Tests: nothing ran yet"
  end
  if vim.api.nvim_buf_get_name(0) ~= last.file then
    vim.cmd.edit(vim.fn.fnameescape(last.file))
  end
  M.run(last.scope == "nearest" and "nearest" or last.scope, last.file, { flags = last.flags })
end

--- `O`: what the runner printed last time
function M.output()
  if not output then
    return log.info "Tests: nothing ran yet"
  end
  local buf = vim.fn.bufnr "tests://output"
  if buf == -1 then
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, "tests://output")
    vim.bo[buf].bufhidden = "hide"
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true, desc = "Tests close output" })
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, output)
  vim.bo[buf].modifiable = false
  vim.cmd "botright 15split"
  vim.api.nvim_win_set_buf(0, buf)
end

--- `T`: the test of this file, or the file of this test (a test that does not exist yet opens as a new buffer)
function M.alternate()
  local buf = vim.api.nvim_get_current_buf()
  local adapter, root = M.adapter(buf)
  if not adapter then
    return log.info "Tests: no tests for this filetype"
  elseif not adapter.alternate then
    return log.info "Tests: Rust keeps its unit tests in the file itself (integration tests live in tests/)"
  end
  local alt = adapter.alternate(vim.api.nvim_buf_get_name(buf), root)
  if not alt then
    return log.info "Tests: no counterpart for this file"
  end
  if not vim.uv.fs_stat(alt) then
    vim.fn.mkdir(vim.fs.dirname(alt), "p")
    log.info("Tests: " .. alt:sub(#root + 2) .. " is new: write it and save")
  end
  vim.cmd.edit(vim.fn.fnameescape(alt))
end

--- The menu entries every language with tests gets: { key, desc, fn }
---@return table[]
function M.maps()
  local function run(scope)
    return function()
      M.run(scope)
    end
  end
  return {
    { "m", "test under cursor", run "nearest" },
    { "M", "test file", run "file" },
    { "A", "test all", run "all" },
    { ".", "test again", M.again },
    { "T", "test file toggle", M.alternate },
    { "O", "test output", M.output },
  }
end

return M
