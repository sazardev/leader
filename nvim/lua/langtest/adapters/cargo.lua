-- ── cargo test ───────────────────────────────────────────────────────────────
-- A test is a function with a test attribute (#[test], #[tokio::test], #[rstest]…); its id is its path inside the crate
-- the way cargo prints it (`tests::adds`, `calc::tests::adds`): the file's module path (src/calc.rs → calc) plus the
-- `mod` blocks around it. Integration tests (tests/x.rs) are their own target (`--test x`). The report is cargo's text:
-- `test calc::tests::adds ... FAILED`, then each failure's output with the `panicked at src/calc.rs:12:9` line.
local ts = require "langtest.ts"

local M = { name = "cargo", filetypes = { "rust" } }

---@param file string
---@return string?
function M.root(file)
  return vim.fs.root(file, "Cargo.toml")
end

---@param path string
---@return boolean
function M.is_test(path)
  return path:find("/tests/", 1, true) ~= nil
end

---@return boolean
function M.detect()
  return true
end

--- The module path of a file inside its crate (pure): src/lib.rs → "", src/calc.rs → "calc", src/a/mod.rs → "a",
--- src/a/b.rs → "a::b"; nil for an integration test (tests/…), which is a crate of its own
---@param rel string relative to the crate root
---@return string?
function M.module_of(rel)
  if rel:match "^tests/" then
    return nil
  end
  local inner = rel:match "^src/(.+)%.rs$"
  if not inner then
    return ""
  end
  if inner == "lib" or inner == "main" then
    return ""
  end
  inner = inner:gsub("/mod$", ""):gsub("^bin/[^/]+$", "")
  return (inner:gsub("/", "::"))
end

---@param ctx LangTestCtx
---@return string[]
function M.command(ctx)
  local cmd = { "cargo", "test" }
  local integration = ctx.rel:match "^tests/([^/]+)%.rs$"
  if ctx.scope ~= "all" and integration then
    vim.list_extend(cmd, { "--test", integration })
  end
  if ctx.scope == "nearest" and ctx.test then
    cmd[#cmd + 1] = ctx.test.id
    if ctx.test.kind == "test" then
      vim.list_extend(cmd, { "--", "--exact" })
    end
  elseif ctx.scope == "file" and not integration then
    local mod = M.module_of(ctx.rel)
    if mod and mod ~= "" then
      cmd[#cmd + 1] = mod .. "::"
    end
  end
  return cmd
end

--- Does a function item carry a test attribute? (the attribute items right before it)
---@param node TSNode
---@param buf integer
---@return boolean
local function is_test_fn(node, buf)
  local prev = node:prev_named_sibling()
  while prev and prev:type() == "attribute_item" do
    local text = ts.text(prev, buf)
    if text:match "^#%[%s*[%w_:]*test%f[%W]" or text:match "^#%[%s*rstest" or text:match "^#%[%s*test_case" then
      return true
    end
    prev = prev:prev_named_sibling()
  end
  return false
end

--- The tests of a buffer
---@param buf integer
---@return LangTestDef[]
function M.tests(buf)
  local root = ts.root(buf, "rust")
  if not root then
    return {}
  end
  local rel = vim.api.nvim_buf_get_name(buf)
  local croot = M.root(rel)
  rel = croot and rel:sub(#croot + 2) or rel
  local base = M.module_of(rel) or ""
  local out = {}
  ts.walk(root, function(node, scope)
    local t = node:type()
    if t == "mod_item" then
      local name = ts.text(node:field("name")[1], buf)
      local srow, erow = node:range(), node:end_()
      local path = vim.list_extend(vim.deepcopy(scope), { name })
      local id = table.concat(vim.list_extend(base ~= "" and { base } or {}, path), "::")
      out[#out + 1] = { id = id, name = name, line = srow + 1, last = erow + 1, kind = "group" }
      return path
    elseif t == "function_item" and is_test_fn(node, buf) then
      local name = ts.text(node:field("name")[1], buf)
      local first = node
      while first:prev_named_sibling() and first:prev_named_sibling():type() == "attribute_item" do
        first = first:prev_named_sibling()
      end
      local srow, erow = first:range(), node:end_()
      local id = table.concat(
        vim.list_extend(base ~= "" and { base } or {}, vim.list_extend(vim.deepcopy(scope), { name })),
        "::"
      )
      out[#out + 1] = { id = id, name = name, line = srow + 1, last = erow + 1, kind = "test" }
    end
  end)
  return out
end

---@param out LangTestOutput
---@param ctx LangTestCtx
---@return LangTestResult[]
function M.parse(out, ctx)
  local text = (out.stdout or "") .. "\n" .. (out.stderr or "")
  local results, by = {}, {}
  local STATUS = { ok = "pass", FAILED = "fail", ignored = "skip" }
  for name, status in ("\n" .. text):gmatch "\ntest ([%w_:]+) %.%.%. (%a+)" do
    if STATUS[status] then
      local r = { id = name, name = name:match "([%w_]+)$", status = STATUS[status] }
      results[#results + 1] = r
      by[name] = r
    end
  end
  -- each failure's block: `---- name stdout ----`, its lines, until the next block or the `failures:` summary
  local name, block = nil, {}
  local function close()
    local r = name and by[name]
    if r then
      local body = table.concat(block, "\n")
      local file, lnum = body:match "panicked at ([^\n:]+):(%d+):%d+"
      local msg = body:match "panicked at [^\n]*\n([^\n]+)" or body:match "panicked at [^\n]*: ([^\n]+)" or "failed"
      r.message, r.detail = vim.trim(msg), vim.trim(body)
      if file then
        r.file = file:sub(1, 1) == "/" and file or (ctx.root .. "/" .. file)
        r.fail_line = tonumber(lnum)
      end
    end
    name, block = nil, {}
  end
  for line in (text .. "\n"):gmatch "([^\n]*)\n" do
    local opened = line:match "^%-%-%-%- ([%w_:]+) stdout %-%-%-%-$"
    if opened then
      close()
      name = opened
    elseif name and (line:match "^failures:%s*$" or line:match "^test result:") then
      close()
    elseif name then
      block[#block + 1] = line
    end
  end
  close()
  return results
end

return M
