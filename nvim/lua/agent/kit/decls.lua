-- ── What a source file declares, in any language (pure, 0 tokens) ────────────
-- The build writes a project one layer at a time, and layers that cannot see each other's code invent it again: two
-- `ProjectRepository` ports, two `timeline_view.dart`. The questions that catch that need the same raw material, the public
-- top-level declarations of every file, so it lives here once: line patterns per language (no parser needed: the files may not
-- compile yet, which is exactly when these checks matter).
--
--   of(path, text)          the public declarations of one file: { name, kind = "type"|"value", line, sig }
--   duplicates(sources)     a public TYPE declared in two files: the layers disagreed about who owns it
--   lost(before, after)     the names a file declared before and does not now
--   users(name, sources)    the files that mention a name (whole word)
local M = {}

---@class KitDecl
---@field name string
---@field kind "type"|"value"
---@field line integer
---@field sig string   the declaration line, trimmed

--- Per language family: { pattern, kind }; the pattern captures the name
---@type table<string, { [1]: string, [2]: "type"|"value" }[]>
local PATTERNS = {
  dart = {
    { "^abstract%s+class%s+([A-Z][%w_]*)", "type" },
    { "^abstract%s+interface%s+class%s+([A-Z][%w_]*)", "type" },
    { "^sealed%s+class%s+([A-Z][%w_]*)", "type" },
    { "^base%s+class%s+([A-Z][%w_]*)", "type" },
    { "^final%s+class%s+([A-Z][%w_]*)", "type" },
    { "^interface%s+class%s+([A-Z][%w_]*)", "type" },
    { "^class%s+([A-Z][%w_]*)", "type" },
    { "^mixin%s+([A-Z][%w_]*)", "type" },
    { "^enum%s+([A-Z][%w_]*)", "type" },
    { "^typedef%s+([A-Z][%w_]*)", "type" },
    { "^extension%s+type%s+([A-Z][%w_]*)", "type" },
  },
  ts = {
    { "^export%s+default%s+class%s+([%w_$]+)", "type" },
    { "^export%s+abstract%s+class%s+([%w_$]+)", "type" },
    { "^export%s+class%s+([%w_$]+)", "type" },
    { "^export%s+interface%s+([%w_$]+)", "type" },
    { "^export%s+type%s+([%w_$]+)", "type" },
    { "^export%s+enum%s+([%w_$]+)", "type" },
    { "^export%s+const%s+enum%s+([%w_$]+)", "type" },
    { "^export%s+async%s+function%s+([%w_$]+)", "value" },
    { "^export%s+function%s+([%w_$]+)", "value" },
    { "^export%s+const%s+([%w_$]+)", "value" },
  },
  go = {
    { "^type%s+([A-Z][%w_]*)%s+struct", "type" },
    { "^type%s+([A-Z][%w_]*)%s+interface", "type" },
    { "^type%s+([A-Z][%w_]*)%s", "type" },
    { "^func%s+([A-Z][%w_]*)%s*[%[%(]", "value" },
  },
  rust = {
    { "^pub%s+struct%s+([%w_]+)", "type" },
    { "^pub%s+enum%s+([%w_]+)", "type" },
    { "^pub%s+trait%s+([%w_]+)", "type" },
    { "^pub%s+type%s+([%w_]+)", "type" },
    { "^pub%s+async%s+fn%s+([%w_]+)", "value" },
    { "^pub%s+fn%s+([%w_]+)", "value" },
  },
  py = {
    { "^class%s+([A-Z][%w_]*)", "type" },
    { "^def%s+([a-z][%w_]*)", "value" },
    { "^async%s+def%s+([a-z][%w_]*)", "value" },
  },
  jvm = {
    { "^public%s+abstract%s+class%s+([A-Z][%w_]*)", "type" },
    { "^public%s+final%s+class%s+([A-Z][%w_]*)", "type" },
    { "^public%s+class%s+([A-Z][%w_]*)", "type" },
    { "^public%s+interface%s+([A-Z][%w_]*)", "type" },
    { "^public%s+enum%s+([A-Z][%w_]*)", "type" },
    { "^public%s+record%s+([A-Z][%w_]*)", "type" },
    { "^open%s+class%s+([A-Z][%w_]*)", "type" },
    { "^data%s+class%s+([A-Z][%w_]*)", "type" },
    { "^sealed%s+class%s+([A-Z][%w_]*)", "type" },
    { "^sealed%s+interface%s+([A-Z][%w_]*)", "type" },
    { "^abstract%s+class%s+([A-Z][%w_]*)", "type" },
    { "^enum%s+class%s+([A-Z][%w_]*)", "type" },
    { "^class%s+([A-Z][%w_]*)", "type" },
    { "^interface%s+([A-Z][%w_]*)", "type" },
    { "^object%s+([A-Z][%w_]*)", "type" },
  },
  swift = {
    { "^public%s+class%s+([A-Z][%w_]*)", "type" },
    { "^public%s+struct%s+([A-Z][%w_]*)", "type" },
    { "^public%s+enum%s+([A-Z][%w_]*)", "type" },
    { "^public%s+protocol%s+([A-Z][%w_]*)", "type" },
    { "^final%s+class%s+([A-Z][%w_]*)", "type" },
    { "^class%s+([A-Z][%w_]*)", "type" },
    { "^struct%s+([A-Z][%w_]*)", "type" },
    { "^enum%s+([A-Z][%w_]*)", "type" },
    { "^protocol%s+([A-Z][%w_]*)", "type" },
  },
}

local FAMILY = {
  dart = "dart",
  ts = "ts",
  tsx = "ts",
  js = "ts",
  jsx = "ts",
  mjs = "ts",
  cjs = "ts",
  go = "go",
  rs = "rust",
  py = "py",
  java = "jvm",
  kt = "jvm",
  kts = "jvm",
  scala = "jvm",
  swift = "swift",
} -- stylua: ignore

---@param path string
---@return string? family
function M.family(path)
  return FAMILY[(path:match "%.([%w]+)$" or ""):lower()]
end

--- Does the file hold the project's own source (not a test, not generated code, not a tool's scaffold)?
---@param path string
---@return boolean
function M.is_source(path)
  if not M.family(path) then
    return false
  end
  local p = path:lower()
  if
    p:match "_test%.go$"
    or p:match "_test%.dart$"
    or p:match "%.test%.[jt]sx?$"
    or p:match "%.spec%.[jt]sx?$"
    or p:match "%.d%.ts$"
    or p:match "%.g%.dart$"
    or p:match "%.freezed%.dart$"
    or p:match "%.gen%.go$"
    or p:match "_generated%."
    or p:match "app_localizations"
    or p:match "^tests?/"
    or p:match "/tests?/"
    or p:match "/__tests__/"
    or p:match "^test_.*%.py$"
    or p:match "/test_[^/]*%.py$"
    or p:match "^build/"
    or p:match "/build/"
    or p:match "^node_modules/"
    or p:match "/node_modules/"
    or p:match "^%.dart_tool/"
    or p:match "^target/"
    or p:match "^rust_builder/"
    or p:match "/cargokit/"
  then
    return false
  end
  return true
end

--- The public top-level declarations of a file, in order
---@param path string
---@param text string
---@return KitDecl[]
function M.of(path, text)
  local patterns = PATTERNS[M.family(path) or ""]
  if not patterns then
    return {}
  end
  local out = {}
  local n = 0
  for line in (text .. "\n"):gmatch "([^\n]*)\n" do
    n = n + 1
    for _, p in ipairs(patterns) do
      local name = line:match(p[1])
      if name then
        out[#out + 1] = { name = name, kind = p[2], line = n, sig = vim.trim((line:gsub("%s*{%s*$", ""))) }
        break
      end
    end
  end
  return out
end

--- Names that two features may legitimately both declare: not worth a report
local GENERIC = {
  State = true,
  Props = true,
  Config = true,
  Options = true,
  Result = true,
  Error = true,
  Model = true,
  Item = true,
  Data = true,
  Event = true,
  Status = true,
  Type = true,
  Context = true,
  Key = true,
  Value = true,
  Node = true,
  Page = true,
  Widget = true,
  App = true,
  Main = true,
  Theme = true,
  Settings = true,
  Params = true,
  Args = true,
  Response = true,
  Request = true,
  Handler = true,
  Service = true,
  Store = true,
  Id = true,
  Kind = true,
} -- stylua: ignore

--- The scope in which one name must be unique: Go declares per package (directory), every other language per project
---@param path string
---@return string
local function scope_of(path)
  if M.family(path) == "go" then
    return "go:" .. (vim.fs.dirname(path) or ".")
  end
  return M.family(path) or "?"
end

---@class KitDuplicate
---@field name string
---@field where { path: string, line: integer }[]

--- Public types declared in two files of the same scope (pure). `sources` = path → text; tests and generated files never
--- count, short and generic names are left alone
---@param sources table<string, string>
---@return KitDuplicate[]
function M.duplicates(sources)
  local by = {} ---@type table<string, { path: string, line: integer }[]>
  local paths = vim.tbl_keys(sources)
  table.sort(paths)
  for _, path in ipairs(paths) do
    if M.is_source(path) then
      for _, d in ipairs(M.of(path, sources[path])) do
        if d.kind == "type" and #d.name > 3 and not GENERIC[d.name] then
          local key = scope_of(path) .. "\1" .. d.name
          by[key] = by[key] or {}
          table.insert(by[key], { path = path, line = d.line })
        end
      end
    end
  end
  local out = {}
  for key, where in pairs(by) do
    local files = {}
    for _, w in ipairs(where) do
      files[w.path] = true
    end
    if vim.tbl_count(files) >= 2 then
      out[#out + 1] = { name = key:match "\1(.*)$", where = where }
    end
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

--- One sentence per duplicate, with what to do
---@param dups KitDuplicate[]
---@return string[]
function M.describe_duplicates(dups)
  local out = {}
  for _, d in ipairs(dups) do
    local at = vim.tbl_map(function(w)
      return ("%s:%d"):format(w.path, w.line)
    end, d.where)
    out[#out + 1] = ("%s is declared in %d files (%s): keep the one the rest of the code imports, move what the others add into it, and delete the duplicate"):format(
      d.name,
      #d.where,
      table.concat(at, ", ")
    )
  end
  return out
end

--- Names declared before and not after (pure)
---@param before KitDecl[]
---@param after KitDecl[]
---@return string[]
function M.lost(before, after)
  local now = {}
  for _, d in ipairs(after) do
    now[d.name] = true
  end
  local out, seen = {}, {}
  for _, d in ipairs(before) do
    if not now[d.name] and not seen[d.name] then
      seen[d.name] = true
      out[#out + 1] = d.name
    end
  end
  return out
end

--- The files whose text mentions `name` as a whole word, except `except`
---@param name string
---@param sources table<string, string>
---@param except string?
---@return string[]
function M.users(name, sources, except)
  local out = {}
  local pattern = "%f[%w_]" .. vim.pesc(name) .. "%f[^%w_]"
  for path, text in pairs(sources) do
    if path ~= except and text:find(pattern) then
      out[#out + 1] = path
    end
  end
  table.sort(out)
  return out
end

return M
