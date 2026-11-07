-- ── dotnet test (xUnit, NUnit, MSTest) ───────────────────────────────────────
-- A test is a method with [Fact], [Theory], [Test], [TestCase], [TestMethod] or [DataTestMethod] (its class and
-- namespace make the id the runner prints). The run writes a TRX report (`--logger trx`); the report is XML and
-- this adapter reads it with patterns (no XML library): definitions give the real class/method (a theory's
-- `Theory(value: 2)` collapses into its method) and results give the outcome, message and stack trace.
local proj = require "utils.csharpproj"
local index = require "utils.csharpindex"

local M = { name = "dotnet", filetypes = { "cs" } }

---@param file string
---@return string?
function M.root(file)
  return proj.find_root(vim.fs.dirname(file))
end

---@param root string
---@return boolean
function M.detect(root)
  return vim.fn.executable "dotnet" == 1 and (proj.solution(root) ~= nil or #proj.projects(root) > 0)
end

---@param path string
---@return boolean
function M.is_test(path)
  if vim.fs.basename(path):match "Tests?%.cs$" or path:find "/[Tt]ests?/" then
    return true
  end
  local text = proj.read(path)
  return text ~= nil
    and (
      text:find "%[Fact" ~= nil
      or text:find "%[Theory" ~= nil
      or text:find "%[Test" ~= nil
      or text:find "%[TestMethod" ~= nil
    )
end

--- The tests a buffer defines
---@param buf integer
---@return LangTestDef[]
function M.tests(buf)
  local info = index.scan_buffer(buf)
  local out = {}
  for _, t in ipairs(info.types) do
    for _, m in ipairs(t.methods) do
      if m.test then
        out[#out + 1] = {
          id = t.full_name .. "." .. m.name,
          name = m.name,
          line = m.line,
          last = m.last,
          kind = "test",
          class = t.full_name,
        }
      end
    end
  end
  return out
end

--- A `dotnet test --filter` expression for the scope (pure)
---@param ctx LangTestCtx
---@return string?
function M.filter(ctx)
  if ctx.scope == "all" then
    return nil
  end
  if ctx.scope == "nearest" and ctx.test then
    return "FullyQualifiedName~" .. ctx.test.id
  end
  local classes = {}
  for _, t in ipairs(ctx.tests or {}) do
    local class = t.class or (t.id:match "^(.*)%.[^.]+$")
    if class and not vim.tbl_contains(classes, class) then
      classes[#classes + 1] = class
    end
  end
  if #classes == 0 and ctx.file then
    -- `T` opened the test file without loading it into a buffer (`M.run("file", alt)`): read it from disk
    local info = index.file(ctx.file)
    for _, t in ipairs(info and info.types or {}) do
      if #t.test_methods > 0 and not vim.tbl_contains(classes, t.full_name) then
        classes[#classes + 1] = t.full_name
      end
    end
  end
  if #classes == 0 then
    return "FullyQualifiedName~__no_tests_in_this_file__"
  end
  local parts = vim.tbl_map(function(class)
    return "FullyQualifiedName~" .. class
  end, classes)
  if #parts == 1 then
    return parts[1]
  end
  return "(" .. table.concat(parts, "|") .. ")"
end

---@param ctx LangTestCtx
---@return string[]
function M.command(ctx)
  local cmd = { "dotnet", "test" }
  local target = proj.test_target(ctx.root)
  if target then
    cmd[#cmd + 1] = target
  end
  vim.list_extend(cmd, { "--nologo", "--verbosity", "quiet" })
  local filter = M.filter(ctx)
  if filter then
    vim.list_extend(cmd, { "--filter", filter })
  end
  local dir = vim.fs.dirname(ctx.report)
  vim.fn.mkdir(dir, "p")
  vim.list_extend(cmd, {
    "--logger",
    "trx;LogFileName=" .. vim.fs.basename(ctx.report),
    "--results-directory",
    dir,
  })
  return cmd
end

---@param text string?
---@return string
local function unescape(text)
  text = (text or ""):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'")
  text = text:gsub("&#x(%x+);", function(hex)
    return vim.fn.nr2char(tonumber(hex, 16))
  end)
  text = text:gsub("&#(%d+);", function(dec)
    return vim.fn.nr2char(tonumber(dec))
  end)
  return (text:gsub("&amp;", "&"))
end

---@param tag string
---@param name string
---@return string?
local function attr(tag, name)
  return tag:match(name .. '="([^"]*)"')
end

local STATUS = {
  Passed = "pass",
  Failed = "fail",
  Error = "fail",
  Timeout = "fail",
  Aborted = "fail",
  PassedButRunAborted = "fail",
  NotExecuted = "skip",
  Inconclusive = "skip",
  Skipped = "skip",
  NotRunnable = "skip",
  Disconnected = "skip",
  Warning = "pass",
}

--- The results of a TRX report (pure; file paths come back as the runner wrote them)
---@param text string?
---@return LangTestResult[]
function M.parse_trx(text)
  text = (text or ""):gsub("^\239\187\191", "") -- UTF-8 BOM
  if text == "" then
    return {}
  end
  local defs = {}
  for attrs, body in text:gmatch "<UnitTest%s+([^>]*)>(.-)</UnitTest>" do
    local id = attr(attrs, "id")
    local method = body:match "<TestMethod%s+([^>]*)/?>"
    if id and method then
      local class = unescape(attr(method, "className") or ""):gsub("%+", ".")
      local name = unescape(attr(method, "name") or "")
      if class ~= "" and name ~= "" then
        defs[id] = { class = class, name = name }
      end
    end
  end
  local by_id = {}
  local function add(tag, body)
    local test_id = attr(tag, "testId")
    local test_name = unescape(attr(tag, "testName") or "")
    local def = test_id and defs[test_id] or nil
    local id = def and (def.class .. "." .. def.name) or (test_name:gsub("%s*%b()%s*$", ""))
    if id == "" then
      return
    end
    local name = def and def.name or (test_name:match "([^.]+)$" or test_name)
    local outcome = attr(tag, "outcome") or ""
    local r = {
      id = id,
      name = name,
      status = STATUS[outcome] or "skip",
    }
    if body then
      local message = body:match "<Message>(.-)</Message>"
      local stack = body:match "<StackTrace>(.-)</StackTrace>"
      r.message = message and unescape(message):match "([^\n]+)" or nil
      r.detail = message and unescape(message) or nil
      if stack then
        stack = unescape(stack)
        local file, line = stack:match "in%s+(.-):line%s+(%d+)"
        if file then
          r.file = vim.trim(file)
          r.fail_line = tonumber(line)
          r.line = r.fail_line
        end
        r.detail = (r.detail and (r.detail .. "\n") or "") .. stack
      end
    end
    local prior = by_id[id]
    -- a theory has one result per case: keep a failure over a pass, never lose it
    if not prior or (r.status == "fail" and prior.status ~= "fail") then
      by_id[id] = r
    end
  end
  -- Results are either `<UnitTestResult …/>` or `<UnitTestResult …>…</UnitTestResult>`: scanning by hand keeps the
  -- first self-closing tag from swallowing the body of a later failure (which is what a plain `.-` pattern does).
  local pos = 1
  while true do
    local start, after = text:find("<UnitTestResult%s+", pos)
    if not start then
      break
    end
    local gt = text:find(">", after + 1, true)
    if not gt then
      break
    end
    local tag = text:sub(after + 1, gt - 1)
    local self_closing = text:sub(gt - 1, gt - 1) == "/"
    if self_closing then
      add(tag:gsub("/%s*$", ""), nil)
      pos = gt + 1
    else
      local close_s, close_e = text:find("</UnitTestResult>", gt + 1, true)
      add(tag, close_s and text:sub(gt + 1, close_s - 1) or "")
      pos = close_e and (close_e + 1) or (gt + 1)
    end
  end
  local out = {}
  for _, r in pairs(by_id) do
    out[#out + 1] = r
  end
  return out
end

---@param out LangTestOutput
---@param ctx LangTestCtx
---@return LangTestResult[]
function M.parse(out, ctx)
  local list = M.parse_trx(out.report)
  for _, r in ipairs(list) do
    if r.file and not r.file:match "^/" then
      r.file = ctx.root .. "/" .. r.file
    end
  end
  return list
end

--- The test file of a class, or the class of a test file (`Foo.cs` ↔ `FooTests.cs`)
---@param path string
---@param root string
---@return string?
function M.alternate(path, root)
  local base = vim.fs.basename(path)
  local dir = vim.fs.dirname(path)
  if base:match "Tests?%.cs$" then
    local name = base:gsub("Tests?%.cs$", ".cs")
    return vim.fs.find(name, { path = root, type = "file", limit = 1 })[1]
  end
  local name = base:gsub("%.cs$", "Tests.cs")
  return vim.fs.find(name, { path = root, type = "file", limit = 1 })[1] or (dir .. "/" .. name)
end

return M
