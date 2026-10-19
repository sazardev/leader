-- ── swift test (Swift Package Manager) ───────────────────────────────────────
-- Both kinds of test SwiftPM runs: XCTest (`func test…()` in a class: id `CalcTests.testAdd`, filter
-- `CalcTests/testAdd`) and Swift Testing (`@Test func adds()`: id `adds`, inside a `@Suite` type `Suite/adds`). The
-- report is the text `swift test` prints: `Test Case 'CalcTests.testAdd' failed` (Linux) or `-[Pkg.CalcTests testAdd]`
-- (macOS), the failure as `File.swift:12: error: …`; Swift Testing's `✘ Test adds() recorded an issue at File.swift:12:5`.
local ts = require "langtest.ts"

local M = { name = "swift", filetypes = { "swift" } }

---@param file string
---@return string?
function M.root(file)
  return vim.fs.root(file, "Package.swift")
end

---@param path string
---@return boolean
function M.is_test(path)
  return path:find("/Tests/", 1, true) ~= nil
end

---@return boolean
function M.detect()
  return true
end

---@param ctx LangTestCtx
---@return string[]
function M.command(ctx)
  local cmd = { "swift", "test" }
  if ctx.scope == "nearest" and ctx.test then
    vim.list_extend(cmd, { "--filter", ctx.test.filter or ctx.test.id })
  elseif ctx.scope == "file" then
    -- the file's test types, as one filter: CalcTests|ParserTests
    local groups = {}
    for _, d in ipairs(ctx.tests or {}) do
      if d.kind == "group" then
        groups[#groups + 1] = d.filter or d.id
      end
    end
    if #groups > 0 then
      vim.list_extend(cmd, { "--filter", table.concat(groups, "|") })
    end
  end
  return cmd
end

--- The tests of a buffer
---@param buf integer
---@return LangTestDef[]
function M.tests(buf)
  local root = ts.root(buf, "swift")
  if not root then
    return {}
  end
  local out = {}
  ts.walk(root, function(node, scope)
    local t = node:type()
    if t == "class_declaration" then -- classes, structs, extensions: the grammar calls them all this
      local name_node = node:field("name")[1]
      local name = ts.text(name_node, buf):match "[%w_]+$" or ""
      local text = ts.text(node, buf)
      local suite = text:match "^%s*@Suite" ~= nil
      if
        text:find(": XCTestCase", 1, true)
        or text:find(":XCTestCase", 1, true)
        or suite
        or text:find("@Test", 1, true)
      then
        local srow, erow = node:range(), node:end_()
        out[#out + 1] = { id = name, name = name, line = srow + 1, last = erow + 1, kind = "group", filter = name }
        return { name, suite = suite or nil }
      end
      return { "\0" }
    elseif t == "function_declaration" and scope[1] ~= "\0" then
      local name = ts.text(node:field("name")[1], buf)
      local text = ts.text(node, buf)
      local srow, erow = node:range(), node:end_()
      local class = scope[1]
      local head = text:sub(1, (text:find("func", 1, true) or 1) - 1) -- the attributes before `func`
      if head:find("@Test", 1, true) then
        out[#out + 1] = {
          id = name,
          name = name,
          line = srow + 1,
          last = erow + 1,
          kind = "test",
          filter = class and (class .. "/" .. name) or name,
        }
      elseif class and name:match "^test" then
        out[#out + 1] = {
          id = class .. "." .. name,
          name = name,
          line = srow + 1,
          last = erow + 1,
          kind = "test",
          filter = class .. "/" .. name,
        }
      end
    end
  end)
  return out
end

---@param out LangTestOutput
---@param ctx LangTestCtx
---@return LangTestResult[]
function M.parse(out, ctx)
  local text = "\n" .. (out.stdout or "") .. "\n" .. (out.stderr or "")
  local results, by = {}, {}
  local function add(id, status)
    local r = by[id]
    if not r then
      r = { id = id, name = id:match "([%w_]+)%(?%)?$" or id, status = status }
      by[id] = r
      results[#results + 1] = r
    elseif status == "fail" then
      r.status = "fail"
    end
    return r
  end
  -- XCTest: Test Case 'CalcTests.testAdd' passed / Test Case '-[Pkg.CalcTests testAdd]' failed
  for case, status in text:gmatch "Test Case '([^']+)' (%a+)" do
    local class, method = case:match "^%-%[[%w_]+%.([%w_]+) ([%w_]+)%]$"
    local id = class and (class .. "." .. method) or case:gsub("^[%w_]+%.([%w_]+%.[%w_]+)$", "%1")
    if status == "passed" or status == "failed" or status == "skipped" then
      add(id, ({ passed = "pass", failed = "fail", skipped = "skip" })[status])
    end
  end
  -- XCTest failure lines: /path/CalcTests.swift:12: error: CalcTests.testAdd : XCTAssertEqual failed: …
  for file, lnum, case, msg in text:gmatch "\n([^\n:]+%.swift):(%d+): error: ([^\n]-) : ([^\n]+)" do
    local class, method = case:match "^%-%[[%w_]+%.([%w_]+) ([%w_]+)%]$"
    local id = class and (class .. "." .. method) or case:gsub("^[%w_]+%.([%w_]+%.[%w_]+)$", "%1")
    local r = add(id, "fail")
    r.message, r.fail_line = vim.trim(msg), tonumber(lnum)
    r.file = file:sub(1, 1) == "/" and file or (ctx.root .. "/" .. file)
  end
  -- Swift Testing: ✔ Test adds() passed after … / ✘ Test adds() recorded an issue at CalcTests.swift:12:5: Expectation failed
  -- (the marks are multibyte: looked for as plain text, a pattern class would read their bytes)
  for line in text:gmatch "[^\n]+" do
    local name, rest = line:match "Test ([%w_]+)%(%)(.*)$"
    if name then
      local status = (line:find("✔", 1, true) and "pass")
        or (line:find("✘", 1, true) and "fail")
        or (line:find("↷", 1, true) and "skip")
      if status then
        local r = add(name, status)
        local file, lnum, msg = rest:match "at ([^\n:]+%.swift):(%d+):%d+: (.+)$"
        if file then
          r.message, r.fail_line = vim.trim(msg), tonumber(lnum)
          -- Swift Testing prints the file's name only: the test file of that name under Tests/
          r.file = file:sub(1, 1) == "/" and file
            or vim.fs.find(file, { path = ctx.root .. "/Tests", type = "file", limit = 1 })[1]
            or (ctx.root .. "/" .. file)
        end
      end
    end
  end
  return results
end

--- The test of a source file: Sources/<Target>/X.swift ↔ Tests/<Target>Tests/XTests.swift
---@param path string
---@param root string
---@return string?
function M.alternate(path, root)
  local rel = path:sub(#root + 2)
  local target, name = rel:match "^Tests/([%w_]+)Tests/(.+)Tests%.swift$"
  if target then
    return ("%s/Sources/%s/%s.swift"):format(root, target, name)
  end
  target, name = rel:match "^Sources/([%w_]+)/(.+)%.swift$"
  if target then
    return ("%s/Tests/%sTests/%sTests.swift"):format(root, target, name)
  end
end

return M
