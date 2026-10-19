-- ── pytest ───────────────────────────────────────────────────────────────────
-- Run with `--junitxml` (xunit1: every case has its file and line), through `uv run` when the project is a uv project,
-- else the project's .venv python, else python3. A test is `test_…` (a function, or a method of a `Test…` class);
-- its id is pytest's node id inside the file (`TestCalc::test_add`), parametrized cases (`test_add[1-2]`) count as it.
local junit = require "langtest.junit"
local ts = require "langtest.ts"

local M = { name = "pytest", filetypes = { "python" } }

---@param file string
---@return string?
function M.root(file)
  return vim.fs.root(file, { "pyproject.toml", "pytest.ini", "setup.cfg", "tox.ini", "setup.py" })
    or vim.fs.root(file, ".git")
end

---@param path string
---@return boolean
function M.is_test(path)
  local base = vim.fs.basename(path)
  return base:match "^test_.*%.py$" ~= nil or base:match "_test%.py$" ~= nil or base == "conftest.py"
end

---@return boolean
function M.detect()
  return true -- a Python file's tests are pytest's (it also runs unittest classes)
end

--- How pytest is started in this project
---@param root string
---@return string[]
function M.runner(root)
  if vim.fn.executable "uv" == 1 and vim.uv.fs_stat(root .. "/uv.lock") then
    return { "uv", "run", "pytest" }
  end
  for _, py in ipairs { "/.venv/bin/python", "/venv/bin/python", "/.venv/Scripts/python.exe" } do
    if vim.fn.executable(root .. py) == 1 then
      return { root .. py, "-m", "pytest" }
    end
  end
  return { "python3", "-m", "pytest" }
end

---@param ctx LangTestCtx
---@return string[]
function M.command(ctx)
  local cmd = M.runner(ctx.root)
  if ctx.scope == "nearest" and ctx.test then
    cmd[#cmd + 1] = ctx.rel .. "::" .. ctx.test.id
  elseif ctx.scope ~= "all" then
    cmd[#cmd + 1] = ctx.rel
  end
  vim.list_extend(cmd, { "-q", "--junitxml=" .. ctx.report, "-o", "junit_family=xunit1", "-p", "no:cacheprovider" })
  return cmd
end

--- The tests of a buffer
---@param buf integer
---@return LangTestDef[]
function M.tests(buf)
  local root = ts.root(buf, "python")
  if not root then
    return {}
  end
  local out = {}
  ts.walk(root, function(node, scope)
    local t = node:type()
    if t == "class_definition" then
      local name = ts.text(node:field("name")[1], buf)
      if name:match "^Test" then
        local first, last = node:range(), node:end_()
        local id = table.concat(vim.list_extend(vim.deepcopy(scope), { name }), "::")
        out[#out + 1] = { id = id, name = name, line = first + 1, last = last + 1, kind = "group" }
        return vim.list_extend(vim.deepcopy(scope), { name })
      end
      return { "\0" } -- a class that is not a test class: nothing inside is collected
    elseif t == "function_definition" and not vim.tbl_contains(scope, "\0") then
      local name = ts.text(node:field("name")[1], buf)
      if name:match "^test" then
        local target = node:parent() and node:parent():type() == "decorated_definition" and node:parent() or node
        local first = target:range()
        local last = target:end_()
        out[#out + 1] = {
          id = table.concat(vim.list_extend(vim.deepcopy(scope), { name }), "::"),
          name = name,
          line = first + 1,
          last = last + 1,
          kind = "test",
        }
      end
      return { "\0" } -- nested functions are not tests
    end
  end)
  return out
end

--- The node id inside the file of a case: `tests.test_calc.TestCalc` + `test_add[1]` → `TestCalc::test_add`
---@param case JunitCase
---@return string
local function id_of(case)
  local name = case.name:gsub("%[.*%]$", "")
  local class = (case.classname or ""):match "%.?([%w_]+)$"
  if class and class:match "^Test" then
    return class .. "::" .. name
  end
  return name
end

---@param out LangTestOutput
---@param ctx LangTestCtx
---@return LangTestResult[]
function M.parse(out, ctx)
  local results = {}
  for _, case in ipairs(junit.cases(out.report or "")) do
    local r = {
      id = id_of(case),
      name = case.name,
      status = case.status,
      file = case.file and (case.file:sub(1, 1) == "/" and case.file or (ctx.root .. "/" .. case.file)) or nil,
      line = case.line and (case.line + 1) or nil, -- xunit1 lines are 0-based
    }
    if case.status == "fail" then
      r.message = case.message or "failed"
      -- the line of the test file the traceback stops at: `tests/test_calc.py:12: AssertionError`
      local fail_line
      for path, lnum in (case.text or ""):gmatch "\n?([^\n:]+%.py):(%d+):" do
        if case.file and vim.endswith(path, vim.fs.basename(case.file)) then
          fail_line = tonumber(lnum)
        end
      end
      r.fail_line = fail_line
      r.detail = case.text
    end
    results[#results + 1] = r
  end
  return results
end

--- The test file of a module: tests/test_<name>.py at the root (where pytest projects keep them), else next to it
---@param path string
---@param root string
---@return string?
function M.alternate(path, root)
  local base = vim.fs.basename(path)
  if M.is_test(path) then
    local name = base:gsub("^test_", ""):gsub("_test%.py$", ".py")
    local found = vim.fs.find(name, { path = root, type = "file", limit = 1 })[1]
    return found
  end
  local existing = vim.fs.find("test_" .. base, { path = root, type = "file", limit = 1 })[1]
  return existing or (root .. "/tests/test_" .. base)
end

return M
