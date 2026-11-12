-- ── go test ──────────────────────────────────────────────────────────────────
-- `go test -json` (test2json) gives one event per test with its Package, so a result never depends on parsing the
-- human output. This is also the only place a broken `_test.go` is seen: `go build` never compiles test files.
-- A test is a top-level `func TestX(t *testing.T)` (or `FuzzX(*testing.F)`, `ExampleX()`); its id is its name.
-- Subtests only exist at run time, so they fold into their parent test's result.
local gotest = require "utils.gotest"
local project = require "utils.project"
local settings = require "core.settings"
local ts = require "langtest.ts"

local M = { name = "go", filetypes = { "go" }, missing = "go is not installed" }

---@param file string
---@return string?
function M.root(file)
  return vim.fs.root(file, "go.mod") or vim.fs.dirname(file)
end

---@param path string
---@return boolean
function M.is_test(path)
  return vim.fs.basename(path):match "_test%.go$" ~= nil
end

---@return boolean
function M.detect()
  return vim.fn.executable "go" == 1
end

--- The module path of a go.mod's text (pure)
---@param text string?
---@return string?
function M.module(text)
  return text and text:match '^%s*module%s+"?([^%s"]+)"?'
end

--- The folder of a package import path (pure): example.com/app/api → <root>/api
---@param root string
---@param pkg string?
---@param module string?
---@return string?
function M.package_dir(root, pkg, module)
  pkg = (pkg or ""):gsub("%s+%[.*%]$", "")
  if module then
    if pkg == module then
      return root
    end
    if pkg:sub(1, #module + 1) == module .. "/" then
      return root .. "/" .. pkg:sub(#module + 2)
    end
  end
end

--- The tests of a buffer: Go only has top-level test functions (`TestMain` is a runner, not a test)
---@param buf integer
---@return LangTestDef[]
function M.tests(buf)
  local root = ts.root(buf, "go")
  if not root then
    return {}
  end
  local out = {}
  ts.walk(root, function(node)
    if node:type() ~= "function_declaration" then
      return
    end
    local name = ts.text(node:field("name")[1], buf)
    if name == "" or name == "TestMain" then
      return
    end
    local params = ts.text(node:field("parameters")[1], buf)
    local is_test = (name:match "^Test" and params:find("testing.T", 1, true))
      or (name:match "^Fuzz" and params:find("testing.F", 1, true))
      or (name:match "^Example")
    if not is_test then
      return
    end
    local first, last = node:range(), node:end_()
    out[#out + 1] = { id = name, name = name, line = first + 1, last = last + 1, kind = "test" }
  end)
  return out
end

---@param path string
---@return string
function M.alternate(path)
  if M.is_test(path) then
    return (path:gsub("_test%.go$", ".go"))
  end
  return (path:gsub("%.go$", "_test.go"))
end

--- A name as a Go regular expression that matches only it
---@param s string
---@return string
local function regex(s)
  return (s:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?{}|\\])", "\\%1"))
end

---@param ctx LangTestCtx
---@return string[]
function M.command(ctx)
  local flags = vim.deepcopy(ctx.flags or {})
  local scope
  if ctx.scope == "all" then
    scope = "./..."
  else
    local dir = vim.fs.dirname(ctx.file)
    scope = dir == ctx.root and "." or ("./" .. dir:sub(#ctx.root + 2))
  end
  if ctx.scope == "nearest" and ctx.test then
    vim.list_extend(flags, { "-run", "^" .. regex(ctx.test.id) .. "$" })
  end
  return gotest.args(flags, scope, { json = true })
end

-- ── the JSON stream ─────────────────────────────────────────────────────────

--- A `file.go:line[:col]: message` inside a test's output
---@param line string?
---@return string? file, integer? line, string? message
local function error_line(line)
  if not line then
    return
  end
  line = line:gsub("\r$", "")
  local file, lnum, col, msg = line:match "^%s*(.-):(%d+):(%d+):%s*(.+)$"
  if not file then
    file, lnum, msg = line:match "^%s*(.-):(%d+):%s*(.+)$"
  else
    msg = ("%s: %s"):format(col, msg) -- keep the column in the message: it is a compiler error
  end
  if file and file ~= "" and not file:match "^%a+://" then
    return file, tonumber(lnum), vim.trim(msg)
  end
end

--- Absolute path of a path printed by the runner (package-relative, or already absolute)
---@param dir string?
---@param path string
---@return string
local function resolve(dir, path)
  path = path:gsub("^%./", "")
  if path:sub(1, 1) == "/" or not dir then
    return path
  end
  return dir .. "/" .. path
end

--- The `_test.go` files of a folder (one level, not its subfolders)
---@param dir string
---@return string[]
local function test_files(dir)
  local files = {}
  local handle = vim.uv.fs_scandir(dir)
  if not handle then
    return files
  end
  while true do
    local name, typ = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if name:match "_test%.go$" then
      if typ == nil then
        local stat = vim.uv.fs_stat(dir .. "/" .. name)
        typ = stat and stat.type
      end
      if typ == "file" then
        files[#files + 1] = name
      end
    end
  end
  return files
end

--- The test file that declares `name`, read only when the event stream did not name a file
---@param dir string
---@param name string
---@param cache table
---@return string?
local function file_of(dir, name, cache)
  local entry = cache[dir]
  if not entry then
    entry = { files = test_files(dir), text = {} }
    cache[dir] = entry
  end
  local base = name:match "^[^/]+" or name
  local pattern = "\nfunc%s+" .. vim.pesc(base) .. "%s*%("
  for _, file in ipairs(entry.files) do
    local text = entry.text[file]
    if not text then
      text = project.read(dir .. "/" .. file) or ""
      entry.text[file] = text
    end
    if ("\n" .. text):find(pattern) then
      return dir .. "/" .. file
    end
  end
end

--- First useful line of a build failure (the `# package` header is not a message)
---@param lines string[]
---@return string?
local function build_message(lines)
  for _, line in ipairs(lines) do
    local text = vim.trim(line)
    if text ~= "" and text:sub(1, 1) ~= "#" then
      return text
    end
  end
end

---@param out LangTestOutput
---@param ctx LangTestCtx
---@return LangTestResult[]
function M.parse(out, ctx)
  local text = (out.stdout or "") .. "\n" .. (out.stderr or "")
  local module = M.module(project.read(ctx.root .. "/go.mod"))
  local by, order, builds = {}, {}, {}
  local cache = {}

  local function package_dir(pkg)
    return M.package_dir(ctx.root, pkg, module)
      or (ctx.scope ~= "all" and ctx.file and ctx.file ~= "" and vim.fs.dirname(ctx.file))
      or nil
  end

  local function record(pkg, test)
    local key = (pkg or "") .. "\0" .. test
    local r = by[key]
    if not r then
      r = { id = test, name = test, status = "running", package = pkg }
      by[key] = r
      order[#order + 1] = r
    end
    return r
  end

  for line in text:gmatch "[^\n]+" do
    local ok, ev = pcall(vim.json.decode, line)
    if ok and type(ev) == "table" then
      local action = ev.Action
      if action == "build-output" then
        local pkg = (ev.ImportPath or ev.Package or ""):gsub("%s+%[.*%]$", "")
        local b = builds[pkg] or { lines = {} }
        builds[pkg] = b
        b.lines[#b.lines + 1] = ev.Output or ""
        local file, lnum, msg = error_line(ev.Output)
        if file then
          b.file = b.file or file
          b.line = b.line or lnum
          b.message = b.message or msg
        end
      elseif action == "build-fail" then
        local pkg = (ev.ImportPath or ev.Package or ""):gsub("%s+%[.*%]$", "")
        local b = builds[pkg] or { lines = {} }
        builds[pkg] = b
        b.failed = true
      elseif ev.Test then
        local r = record(ev.Package, ev.Test)
        if action == "pass" or action == "fail" or action == "skip" then
          r.status = action
          r.elapsed = ev.Elapsed
        elseif action == "output" then
          local file, lnum, msg = error_line(ev.Output)
          if file then
            r.file = r.file or resolve(package_dir(ev.Package), file)
            r.fail_line = r.fail_line or lnum
            r.message = r.message or msg
          end
          r.detail = (r.detail or "") .. (ev.Output or "")
          local panic = (ev.Output or ""):match "^%s*(panic:%s*[^\n]+)"
          if panic then
            r.panic = panic
          end
        end
      elseif action == "fail" and ev.FailedBuild then
        local pkg = (ev.FailedBuild or ""):gsub("%s+%[.*%]$", "")
        local b = builds[pkg] or { lines = {} }
        builds[pkg] = b
        b.failed = true
      end
    end
  end

  local list = {}
  for _, r in ipairs(order) do
    if not r.id:find("/", 1, true) and r.status ~= "running" then
      local dir = package_dir(r.package)
      if not r.file and dir then
        r.file = file_of(dir, r.id, cache)
      end
      if r.status == "fail" then
        local sub
        for _, child in ipairs(order) do
          if child.status == "fail" and child.id:sub(1, #r.id + 1) == r.id .. "/" then
            sub = sub or child
          end
        end
        if sub then
          r.message = r.message or sub.message or sub.panic
          r.fail_line = r.fail_line or sub.fail_line
          r.file = r.file or sub.file
          r.detail = r.detail or sub.detail
        end
        r.message = r.message or r.panic or "failed"
      end
      list[#list + 1] = r
    end
  end

  -- `go test` reports a broken test file as a build failure with no test event at all
  for pkg, b in pairs(builds) do
    if b.failed then
      local dir = package_dir(pkg)
      list[#list + 1] = {
        id = "build:" .. pkg,
        name = "build " .. (pkg ~= "" and pkg or ctx.file),
        status = "fail",
        file = b.file and resolve(dir, b.file) or nil,
        fail_line = b.line,
        message = b.message or build_message(b.lines) or "build failed",
        detail = table.concat(b.lines, ""),
        build = true,
      }
    end
  end
  return list
end

--- The human output of `-json`, for `O` (and short when `settings.go.test.verbose` is off)
---@param out LangTestOutput
---@return string[]
function M.display(out)
  local text = (out.stdout or "") .. "\n" .. (out.stderr or "")
  local shown = {}
  for line in text:gmatch "[^\n]+" do
    local ok, ev = pcall(vim.json.decode, line)
    if ok and type(ev) == "table" and type(ev.Output) == "string" then
      local chunk = ev.Output:gsub("\r$", "")
      if chunk:sub(-1) == "\n" then
        chunk = chunk:sub(1, -2)
      end
      for part in (chunk .. "\n"):gmatch "([^\n]*)\n" do
        shown[#shown + 1] = part
      end
    else
      shown[#shown + 1] = line
    end
  end
  if (settings.go.test or {}).verbose == false then
    shown = vim.tbl_filter(function(line)
      return not (line:match "^=== " or line:match "^--- PASS" or line == "PASS" or line:match "^ok%s")
    end, shown)
  end
  return shown
end

return M
