-- ── vitest, jest, bun test ───────────────────────────────────────────────────
-- Which runner a project uses comes from its package.json (vitest or jest in its dependencies, else `bun test` in a bun
-- project), run with the package manager's own exec (pnpm exec, yarn, bunx, npx --no-install: never a download).
-- vitest and jest write the same JSON report (`--reporter=json`, `--json --testLocationInResults`), bun a JUnit one.
-- A test is a call to it/test (a group: describe), `.only`/`.skip`/`.each` included; its id is the names from the
-- outermost describe down, joined with " > ".
local junit = require "langtest.junit"
local ts = require "langtest.ts"

local M = { name = "js", filetypes = { "typescript", "typescriptreact", "javascript", "javascriptreact" } }

local CALLS = { it = "test", test = "test", describe = "group", suite = "group", bench = "test" }

---@param file string
---@return string?
function M.root(file)
  return vim.fs.root(file, "package.json")
end

---@param path string
---@return boolean
function M.is_test(path)
  return path:match "%.test%.[cm]?[jt]sx?$" ~= nil
    or path:match "%.spec%.[cm]?[jt]sx?$" ~= nil
    or path:find "/__tests__/" ~= nil
end

--- The runner of a project (pure but for reading package.json): "vitest" | "jest" | "bun" | nil
---@param root string
---@return string?
function M.runner(root)
  local ok, pkg = pcall(vim.json.decode, require("utils.project").read(root .. "/package.json") or "")
  pkg = ok and type(pkg) == "table" and pkg or {}
  local deps = vim.tbl_extend("force", pkg.dependencies or {}, pkg.devDependencies or {})
  local script = type(pkg.scripts) == "table" and pkg.scripts.test or ""
  if deps.vitest or script:find("vitest", 1, true) then
    return "vitest"
  elseif deps.jest or script:find("jest", 1, true) then
    return "jest"
  elseif
    vim.uv.fs_stat(root .. "/bun.lock")
    or vim.uv.fs_stat(root .. "/bun.lockb")
    or script:find("bun test", 1, true)
  then
    return "bun"
  end
end

---@param root string
---@return boolean
function M.detect(root)
  return M.runner(root) ~= nil
end

--- How the project's own binaries are run
---@param root string
---@return string[]
local function exec(root)
  if vim.uv.fs_stat(root .. "/pnpm-lock.yaml") then
    return { "pnpm", "exec" }
  elseif vim.uv.fs_stat(root .. "/yarn.lock") then
    return { "yarn" }
  elseif vim.uv.fs_stat(root .. "/bun.lock") or vim.uv.fs_stat(root .. "/bun.lockb") then
    return { "bunx" }
  end
  return { "npx", "--no-install" }
end

--- A test name as a regular expression that matches only it
---@param s string
---@return string
local function regex(s)
  return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?{}|\\]", "\\%0"))
end

---@param ctx LangTestCtx
---@return string[]
function M.command(ctx)
  local runner = M.runner(ctx.root)
  local cmd
  if runner == "bun" then
    cmd = { "bun", "test", "--reporter=junit", "--reporter-outfile=" .. ctx.report }
  elseif runner == "jest" then
    cmd =
      vim.list_extend(exec(ctx.root), { "jest", "--json", "--testLocationInResults", "--outputFile=" .. ctx.report })
  else
    cmd = vim.list_extend(exec(ctx.root), { "vitest", "run", "--reporter=json", "--outputFile=" .. ctx.report })
  end
  if ctx.scope ~= "all" then
    cmd[#cmd + 1] = ctx.rel
  end
  if ctx.scope == "nearest" and ctx.test then
    -- the runners match the name against the full name, describes and test joined by spaces
    local full = ctx.test.id:gsub(" > ", " ")
    vim.list_extend(cmd, { "-t", "^" .. regex(full) .. (ctx.test.kind == "test" and "$" or "") })
  end
  return cmd
end

--- The tests of a buffer
---@param buf integer
---@return LangTestDef[]
function M.tests(buf)
  local lang = vim.bo[buf].filetype:match "react$" and "tsx"
    or (vim.bo[buf].filetype == "javascript" and "javascript" or "typescript")
  local root = ts.root(buf, lang)
  if not root then
    return {}
  end
  local out = {}
  ts.walk(root, function(node, scope)
    if node:type() ~= "call_expression" then
      return nil
    end
    local fn = node:field("function")[1]
    -- describe.each(...)(name, fn): the call whose function is itself a call
    while fn and fn:type() == "call_expression" do
      fn = fn:field("function")[1]
    end
    local base = fn and (fn:type() == "member_expression" and fn:field("object")[1] or fn)
    local kind = base and base:type() == "identifier" and CALLS[ts.text(base, buf)]
    if not kind then
      return nil
    end
    local args = node:field("arguments")[1]
    local first = args and args:named_child(0)
    local name = first and ts.literal(ts.text(first, buf))
    if not name then
      return nil
    end
    local id = table.concat(vim.list_extend(vim.deepcopy(scope), { name }), " > ")
    local srow = node:range()
    local erow = node:end_()
    out[#out + 1] = { id = id, name = name, line = srow + 1, last = erow + 1, kind = kind }
    return vim.list_extend(vim.deepcopy(scope), { name })
  end)
  return out
end

--- The first `file:line` of the test file in a stack trace
---@param text string
---@param file string
---@return integer?
local function line_in(text, file)
  local base = vim.pesc(vim.fs.basename(file))
  return tonumber(text:match(base .. ":(%d+):%d+"))
end

---@param out LangTestOutput
---@param ctx LangTestCtx
---@return LangTestResult[]
function M.parse(out, ctx)
  local results = {}
  if M.runner(ctx.root) == "bun" then
    for _, case in ipairs(junit.cases(out.report or "")) do
      local id = (case.classname and case.classname ~= "" and (case.classname .. " > ") or "") .. case.name
      results[#results + 1] = {
        id = id,
        name = case.name,
        status = case.status,
        file = case.file and (case.file:sub(1, 1) == "/" and case.file or (ctx.root .. "/" .. case.file)) or nil,
        line = case.line,
        message = case.status == "fail" and (case.message or "failed") or nil,
        detail = case.text,
        fail_line = case.text and ctx.file and line_in(case.text, ctx.file) or nil,
      }
    end
    return results
  end
  local ok, data = pcall(vim.json.decode, out.report or "", { luanil = { object = true, array = true } })
  if not ok or type(data) ~= "table" then
    return results
  end
  local STATUS =
    { passed = "pass", failed = "fail", pending = "skip", skipped = "skip", todo = "skip", disabled = "skip" }
  for _, file in ipairs(data.testResults or {}) do
    for _, a in ipairs(file.assertionResults or {}) do
      local names = vim.list_extend(vim.deepcopy(a.ancestorTitles or {}), { a.title })
      local failure = table.concat(a.failureMessages or {}, "\n")
      results[#results + 1] = {
        id = table.concat(names, " > "),
        name = a.title,
        status = STATUS[a.status] or "skip",
        file = file.name,
        line = a.location and a.location.line or nil,
        message = a.status == "failed" and (failure:match "[^\n]+" or "failed") or nil,
        detail = failure ~= "" and failure or nil,
        fail_line = failure ~= "" and file.name and line_in(failure, file.name) or nil,
      }
    end
  end
  return results
end

--- The test of a module next to it (x.ts ↔ x.test.ts, the extension kept), or back
---@param path string
---@return string
function M.alternate(path)
  local stem, ext = path:match "^(.-)%.test%.([%w]+)$"
  if not stem then
    stem, ext = path:match "^(.-)%.spec%.([%w]+)$"
  end
  if stem then
    return stem .. "." .. ext
  end
  local base, e = path:match "^(.-)%.([%w]+)$"
  local spec = base .. ".spec." .. e
  if vim.uv.fs_stat(spec) then
    return spec
  end
  return base .. ".test." .. e
end

return M
