-- ── Dart / Flutter tests inside the editor ───────────────────────────────────
-- `<leader>dm` runs the test (or group) under the cursor, `<leader>dM` the file, `<leader>dA` the whole package,
-- `<leader>d.` the last run again. `flutter test` or `dart test` (whichever the package is) with the JSON reporter
-- (darttest/parse.lua): each test line gets a mark as it finishes (✓ passed, ✗ failed, ○ skipped, … running), a failure
-- becomes a diagnostic on the line the stack trace points at (the `expect` that failed) with the expected/actual text
-- and what the test printed, the failures go to the quickfix list, and one note sums up the run. Results are kept per
-- file, so a test file opened later shows them too. `<leader>dT` jumps between a file and its test (creating the test).
local log = require "utils.log"
local parse = require "darttest.parse"

local M = {}

local NS = vim.api.nvim_create_namespace "darttest" -- diagnostics of failed tests
local MARKS = vim.api.nvim_create_namespace "darttest.marks"
local TEST_CALLS =
  { test = true, testWidgets = true, group = true, testGoldens = true, blocTest = true, patrolTest = true }
local SIGN = { pass = "✓", fail = "✗", skip = "○", running = "…" }
local HL = { pass = "DartTestPass", fail = "DartTestFail", skip = "DartTestSkip", running = "DartTestRunning" }

---@type table<string, table<string, DartTest>> results per test file: full test name → its last result
local results = {}
---@type { proc: vim.SystemObj?, state: DartTestState, spec: table, started: integer }?
local current
---@type table? the last run's spec, for `again`
local last

---@param buf integer?
---@return string?
function M.root(buf)
  return vim.fs.root(buf or 0, "pubspec.yaml")
end

---@param root string
---@return boolean
local function is_flutter(root)
  local f = io.open(root .. "/pubspec.yaml", "r")
  if not f then
    return false
  end
  local text = f:read "*a"
  f:close()
  return text:find "sdk:%s*flutter" ~= nil
end

--- The command of a run: `flutter test` / `dart test`, JSON reporter, the file and the name filter
---@param root string
---@param file string? absolute
---@param name string?
---@param flutter boolean
---@return string[]
function M.command(root, file, name, flutter)
  local cmd = flutter and { "flutter", "test" } or { "dart", "test" }
  vim.list_extend(cmd, { "--reporter", "json" })
  if file then
    cmd[#cmd + 1] = file:sub(1, #root + 1) == root .. "/" and file:sub(#root + 2) or file
  end
  if name then
    vim.list_extend(cmd, { "--plain-name", name })
  end
  return cmd
end

-- ── what is under the cursor ────────────────────────────────────────────────

--- The test or group around a position: { name = full name, kind = "test"|"group" }, nil outside any
---@param buf integer
---@param row integer 0-based
---@param col integer 0-based
---@return { name: string, kind: string }?
function M.nearest(buf, row, col)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "dart")
  if not ok or not parser then
    return nil
  end
  local tree = parser:parse()[1]
  -- on the indentation or on the call's own name (`group(`): the call that starts on this line
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  col = math.max(col, (line:find "%S" or 1) - 1)
  local node = tree:root():named_descendant_for_range(row, col, row, col)
  local after = node and node:type() == "identifier" and node:next_named_sibling()
  if after and after:type() == "selector" then
    node = after
  end
  local names, kind = {}, nil
  while node do
    -- a call in Dart's grammar: `test` (identifier) followed by a selector holding the arguments
    if node:type() == "selector" and node:named_child(0) and node:named_child(0):type() == "argument_part" then
      local callee = node:prev_named_sibling()
      local fn = callee and callee:type() == "identifier" and vim.treesitter.get_node_text(callee, buf)
      if fn and TEST_CALLS[fn] then
        local args = node:named_child(0):named_child(0) -- arguments
        local first = args and args:named_child(0) -- argument
        local literal = first and first:named_child(0)
        local name = literal
          and literal:type() == "string_literal"
          and parse.literal(vim.treesitter.get_node_text(literal, buf))
        if not name then
          return nil -- an interpolated name cannot be matched by --plain-name
        end
        table.insert(names, 1, name)
        kind = kind or (fn == "group" and "group" or "test")
      end
    end
    node = node:parent()
  end
  if #names == 0 then
    return nil
  end
  return { name = table.concat(names, " "), kind = kind }
end

-- ── showing results ─────────────────────────────────────────────────────────

--- Repaints the marks and diagnostics of a test file from its stored results
---@param file string
function M.render(file)
  local buf = vim.fn.bufnr(file)
  if buf < 0 or not vim.api.nvim_buf_is_loaded(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, MARKS, 0, -1)
  local count = vim.api.nvim_buf_line_count(buf)
  local diags = {}
  for _, t in pairs(results[file] or {}) do
    if t.lnum and t.lnum <= count then
      local text = t.status == "pass" and t.ms and ("%d ms"):format(t.ms) or nil
      vim.api.nvim_buf_set_extmark(buf, MARKS, t.lnum - 1, 0, {
        sign_text = SIGN[t.status],
        sign_hl_group = HL[t.status],
        virt_text = text and { { text, "DartTestTime" } } or nil,
        virt_text_pos = "eol",
        priority = 20,
      })
    end
    if t.status == "fail" then
      for _, e in ipairs(t.errors) do
        local lnum = math.min(e.lnum or t.lnum or 1, count)
        local message = e.message
        if #t.prints > 0 then
          message = message .. "\n\nprinted:\n" .. table.concat(t.prints, "\n")
        end
        diags[#diags + 1] = {
          lnum = lnum - 1,
          col = 0,
          message = message,
          source = "test: " .. t.name,
          severity = vim.diagnostic.severity.ERROR,
        }
      end
    end
  end
  table.sort(diags, function(a, b)
    return a.lnum < b.lnum
  end)
  vim.diagnostic.set(NS, buf, diags)
end

---@param test DartTest
local function store(test)
  if not test.file then
    return
  end
  results[test.file] = results[test.file] or {}
  results[test.file][test.name] = test
  M.render(test.file)
end

--- The run is over: quickfix, note, statusline
local function finish(run, code)
  local state = run.state
  local s = parse.summary(state)
  local failures = parse.failures(state)
  local secs = (vim.uv.now() - run.started) / 1000
  local items = {}
  for _, t in ipairs(failures) do
    local e = t.errors[1]
    items[#items + 1] = {
      filename = t.file,
      lnum = (e and e.lnum) or t.lnum or 1,
      text = t.name .. ": " .. ((e and e.message or "failed"):match "[^\n]+" or "failed"),
    }
  end
  vim.fn.setqflist({}, " ", { title = "Dart tests", items = items })

  local total = s.pass + s.fail
  if total + s.skip == 0 then
    local tail = (run.output[#run.output] or ""):sub(1, 160)
    return log.warn(
      ("Tests: none ran (exit %d)%s"):format(code, tail ~= "" and (" · " .. tail) or "")
        .. " · <leader>dw shows the output"
    )
  end
  local skipped = s.skip > 0 and (" · %d skipped"):format(s.skip) or ""
  if s.fail > 0 then
    log.error(
      ("Tests failed: %d of %d%s · %s (%.1fs, quickfix has them)"):format(
        s.fail,
        total,
        skipped,
        failures[1].name,
        secs
      )
    )
  else
    log.info(("Tests passed: %d%s (%.1fs)"):format(s.pass, skipped, secs))
  end
end

-- ── running ─────────────────────────────────────────────────────────────────

---@param spec { root: string, file: string?, name: string?, label: string }
local function start(spec)
  if current and current.proc then
    current.proc:kill "sigterm"
    log.info "Tests: the previous run was stopped"
  end
  -- a file (or everything) starts clean; a single test keeps its file's other results
  if not spec.name then
    for file in pairs(results) do
      if not spec.file or file == spec.file then
        results[file] = {}
        M.render(file)
      end
    end
  end
  local run = {
    state = parse.new(spec.root),
    spec = spec,
    started = vim.uv.now(),
    output = {},
  }
  current, last = run, spec
  local pending = ""
  local function on_output(_, data)
    if not data then
      return
    end
    vim.schedule(function()
      local lines = vim.split(pending .. data, "\n", { plain = true })
      pending = table.remove(lines)
      for _, line in ipairs(lines) do
        run.output[#run.output + 1] = line
        local test = parse.feed(run.state, line)
        if test then
          store(test)
        end
      end
    end)
  end
  local cmd = M.command(spec.root, spec.file, spec.name, is_flutter(spec.root))
  local ok, proc = pcall(vim.system, cmd, { cwd = spec.root, stdout = on_output, stderr = on_output }, function(out)
    vim.schedule(function()
      if pending ~= "" then
        run.output[#run.output + 1] = pending
        local test = parse.feed(run.state, pending)
        if test then
          store(test)
        end
      end
      run.proc = nil
      if current == run and out.signal ~= 15 then
        finish(run, out.code)
      end
    end)
  end)
  if not ok then
    current = nil
    return log.error("Tests: could not run " .. cmd[1] .. " (" .. tostring(proc) .. ")")
  end
  run.proc = proc
  log.info("Tests: running " .. spec.label)
end

--- `scope`: "nearest" (the test or group under the cursor; the file when there is none), "file", "all", "again"
---@param scope string
function M.run(scope)
  if scope == "again" then
    if not last then
      return log.info "Tests: nothing ran yet (<leader>dm runs the test under the cursor)"
    end
    return start(last)
  end
  local buf = vim.api.nvim_get_current_buf()
  local root = M.root(buf)
  if not root then
    return log.warn "Tests: no pubspec.yaml above this file"
  end
  if scope == "all" then
    return start { root = root, label = "all the tests of " .. vim.fs.basename(root) }
  end
  local file = vim.api.nvim_buf_get_name(buf)
  if not file:match "_test%.dart$" then
    return log.warn "Tests: this is not a test file (<leader>dT jumps to its test)"
  end
  if vim.bo[buf].modified then
    vim.cmd "silent write"
  end
  local spec = { root = root, file = file, label = vim.fs.basename(file) }
  if scope == "nearest" then
    local pos = vim.api.nvim_win_get_cursor(0)
    local near = M.nearest(buf, pos[1] - 1, pos[2])
    if near then
      spec.name, spec.label = near.name, ("%s '%s'"):format(near.kind, near.name)
    end
  end
  start(spec)
end

--- Statusline: "test …" with what finished so far ("test ✓12 ✗1 …"); "" when nothing runs
---@return string
function M.statusline()
  if not (current and current.proc) then
    return ""
  end
  local s = parse.summary(current.state)
  local parts = { "test" }
  if s.pass > 0 then
    parts[#parts + 1] = "✓" .. s.pass
  end
  if s.fail > 0 then
    parts[#parts + 1] = "✗" .. s.fail
  end
  parts[#parts + 1] = "…"
  return table.concat(parts, " ")
end

--- Did the running test run see failures? (the statusline chip turns red)
---@return boolean
function M.failing()
  return current ~= nil and parse.summary(current.state).fail > 0
end

--- The raw output of the last run in a scratch window (toolchain warnings, compile errors that stop a run before any
--- test, the JSON events)
function M.show_output()
  if not current then
    return log.info "Tests: nothing ran yet"
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, current.output)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  vim.cmd "botright split"
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_height(0, math.max(8, math.floor(vim.o.lines * 0.35)))
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true })
end

-- ── the test of a file and back ─────────────────────────────────────────────

--- `lib/a/b.dart` ↔ `test/a/b_test.dart` (inside the package root)
---@param root string
---@param file string absolute
---@return string? other
function M.counterpart(root, file)
  local rel = file:sub(#root + 2)
  if rel:match "^test/.+_test%.dart$" then
    return root .. "/lib/" .. rel:sub(6):gsub("_test%.dart$", ".dart")
  elseif rel:match "^lib/.+%.dart$" then
    return root .. "/test/" .. rel:sub(5):gsub("%.dart$", "_test.dart")
  end
end

--- A new test file for `source` (not written to disk until you save)
---@param root string
---@param source string absolute path of lib/…
---@return string[]
function M.skeleton(root, source)
  local f = io.open(root .. "/pubspec.yaml", "r")
  local pubspec = f and f:read "*a" or ""
  if f then
    f:close()
  end
  local package = pubspec:match "^name:%s*([%w_]+)" or pubspec:match "\nname:%s*([%w_]+)" or vim.fs.basename(root)
  local flutter = pubspec:find "sdk:%s*flutter" ~= nil
  local base = vim.fn.fnamemodify(source, ":t:r")
  local subject = (base:gsub("^%l", string.upper):gsub("_(%w)", string.upper))
  return {
    flutter and "import 'package:flutter_test/flutter_test.dart';" or "import 'package:test/test.dart';",
    ("import 'package:%s/%s';"):format(package, source:sub(#root + 6)),
    "",
    "void main() {",
    ("  group('%s', () {"):format(subject),
    "    test('', () {});",
    "  });",
    "}",
  }
end

function M.toggle_file()
  local buf = vim.api.nvim_get_current_buf()
  local root = M.root(buf)
  local file = vim.api.nvim_buf_get_name(buf)
  local other = root and M.counterpart(root, file)
  if not other then
    return log.warn "Tests: only for files under lib/ and test/ of a package"
  end
  local exists = vim.uv.fs_stat(other) ~= nil
  vim.cmd.edit(vim.fn.fnameescape(other))
  if not exists and other:match "_test%.dart$" then
    vim.api.nvim_buf_set_lines(0, 0, -1, false, M.skeleton(root, file))
    vim.api.nvim_win_set_cursor(0, { 6, 10 })
    log.info "Tests: new test file (not saved yet)"
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("DartTest", { clear = true })
  -- a test file opened after the run shows its results
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = group,
    pattern = "*_test.dart",
    callback = function(ev)
      local file = vim.api.nvim_buf_get_name(ev.buf)
      if results[file] then
        M.render(file)
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if current and current.proc then
        current.proc:kill "sigterm"
      end
    end,
  })
end

return M
