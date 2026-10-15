-- ── `dart test` / `flutter test` JSON reporter, line by line ─────────────────
-- Pure. Feeds the `--reporter json` events (one JSON object per line; other lines, such as Flutter's toolchain
-- warnings, are skipped) and keeps each test: its full name (groups included), file and line (`root_line`/`root_url`
-- for `testWidgets`, whose own `line`/`url` point into flutter_test), state, errors (with the line of the test file the
-- stack trace points at), prints and duration.
local M = {}

---@class DartTestError
---@field message string
---@field lnum integer? 1-based line in the test's file the stack trace points at

---@class DartTest
---@field id integer
---@field name string full name: groups and test, separated by spaces (what `--plain-name` matches)
---@field file string? absolute path
---@field lnum integer? 1-based
---@field status string "running" | "pass" | "fail" | "skip"
---@field errors DartTestError[]
---@field prints string[]
---@field start integer? ms since the run started
---@field ms integer? duration

---@class DartTestState
---@field tests table<integer, DartTest>
---@field order integer[] ids in the order they started
---@field suites table<integer, string> suite id → path
---@field done boolean
---@field success boolean?
---@field root string package root (relative paths in suites and stack traces are resolved against it)

---@param root string
---@return DartTestState
function M.new(root)
  return { tests = {}, order = {}, suites = {}, done = false, root = root }
end

---@param root string
---@param path string? file:// URL, absolute or relative path
---@return string?
local function absolute(root, path)
  if not path or path == vim.NIL then
    return nil
  end
  path = path:gsub("^file://", "")
  if path:sub(1, 1) ~= "/" then
    path = root .. "/" .. path
  end
  return path
end

--- The first frame of a stack trace that is in `file` ("test/calc_test.dart 11:9  main.<fn>")
---@param trace string?
---@param file string? absolute
---@param root string
---@return integer?
function M.trace_line(trace, file, root)
  if not trace or not file then
    return nil
  end
  for frame in trace:gmatch "[^\n]+" do
    local path, lnum = frame:match "^(%S+)%s+(%d+):%d+"
    if path and absolute(root, path) == file then
      return tonumber(lnum)
    end
  end
end

--- Feeds one line of output. Returns the test the event was about (started, finished, failed), if any.
---@param state DartTestState
---@param line string
---@return DartTest?
function M.feed(state, line)
  if line:sub(1, 1) ~= "{" then
    return nil
  end
  local ok, e = pcall(vim.json.decode, line)
  if not ok or type(e) ~= "table" then
    return nil
  end

  if e.type == "suite" then
    state.suites[e.suite.id] = absolute(state.root, e.suite.path)
  elseif e.type == "testStart" then
    local t = e.test
    if t.name:match "^loading " then
      return nil -- the suite's own loading pseudo-test
    end
    local url = t.root_url ~= vim.NIL and t.root_url or t.url
    local lnum = t.root_line ~= vim.NIL and t.root_line or t.line
    local test = {
      id = t.id,
      name = t.name,
      file = absolute(state.root, url ~= vim.NIL and url or nil) or state.suites[t.suiteID],
      lnum = lnum ~= vim.NIL and lnum or nil,
      status = "running",
      errors = {},
      prints = {},
      start = e.time,
    }
    state.tests[t.id] = test
    state.order[#state.order + 1] = t.id
    return test
  elseif e.type == "error" then
    local test = state.tests[e.testID]
    if test then
      test.errors[#test.errors + 1] = {
        message = vim.trim(e.error or ""),
        lnum = M.trace_line(e.stackTrace, test.file, state.root),
      }
      return test
    end
  elseif e.type == "print" then
    local test = state.tests[e.testID]
    if test and e.messageType ~= "skip" then
      test.prints[#test.prints + 1] = e.message
    end
  elseif e.type == "testDone" then
    local test = state.tests[e.testID]
    if test then
      if e.skipped then
        test.status = "skip"
      else
        test.status = e.result == "success" and "pass" or "fail"
      end
      test.ms = test.start and (e.time - test.start) or nil
      return test
    end
  elseif e.type == "done" then
    state.done, state.success = true, e.success
  end
end

--- Counts of a run
---@param state DartTestState
---@return { pass: integer, fail: integer, skip: integer, running: integer }
function M.summary(state)
  local s = { pass = 0, fail = 0, skip = 0, running = 0 }
  for _, id in ipairs(state.order) do
    local status = state.tests[id].status
    s[status] = s[status] + 1
  end
  return s
end

--- Failed tests, in the order they ran
---@param state DartTestState
---@return DartTest[]
function M.failures(state)
  local out = {}
  for _, id in ipairs(state.order) do
    if state.tests[id].status == "fail" then
      out[#out + 1] = state.tests[id]
    end
  end
  return out
end

--- Test name a call starts with: `test('sums', …)` → "sums"; nil for interpolated or non-literal names
---@param literal string the string literal as written (quotes included)
---@return string?
function M.literal(literal)
  local body = literal:match "^r?'''(.*)'''$"
    or literal:match '^r?"""(.*)"""$'
    or literal:match "^r?'(.*)'$"
    or literal:match '^r?"(.*)"$'
  if not body or (not literal:match "^r" and body:find("$", 1, true)) then
    return nil
  end
  return (body:gsub("\\(.)", "%1"))
end

return M
