-- ── Project index for DDD ────────────────────────────────────────────────────
-- Walks the project ONCE (async, in batches, so nvim does not freeze) and stores per file: its layer
-- (by directory), its imports (and which layer or framework they point to) and the type definitions it declares.
-- Caches by mtime+size: later runs only re-read the files that changed.
local imports = require "agent.ddd.imports"
local layers = require "agent.ddd.layers"
local scopes = require "agent.context.scopes"
local settings = require("core.settings").agent.ddd

local M = {}

local CHUNK = 40
local MAX_BYTES = 300000

local ROOT_MARKERS = {
  ".git",
  "go.mod",
  "package.json",
  "pyproject.toml",
  "Cargo.toml",
  "pom.xml",
  "build.gradle",
  "build.gradle.kts",
  "pubspec.yaml",
}

--- Project root of a buffer
---@param buf integer
---@return string
function M.root(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  return vim.fs.root(name ~= "" and name or buf, ROOT_MARKERS) or vim.fn.getcwd()
end

---@class DddCtx
---@field root string
---@field go_module string?

--- Is it an import of the project itself? Only those are assigned to a layer: `database/sql` is not the `database` layer.
---@param spec string
---@param ext string
---@param ctx DddCtx
---@return boolean
local function is_internal(spec, ext, ctx)
  if ext == "go" then
    local m = ctx.go_module
    return m ~= nil and (spec == m or spec:sub(1, #m + 1) == m .. "/")
  elseif ext == "ts" or ext == "tsx" or ext == "js" or ext == "jsx" or ext == "mjs" or ext == "cjs" then
    return spec:find "^%." ~= nil
      or spec:find "^@/" ~= nil
      or spec:find "^~/" ~= nil
      or spec:find "^src/" ~= nil
      or spec:find "^#" ~= nil
  elseif ext == "py" then
    if spec:find "^%." then
      return true
    end
    local top = spec:match "^[^%.]+"
    return top ~= nil
      and (vim.uv.fs_stat(ctx.root .. "/" .. top) ~= nil or vim.uv.fs_stat(ctx.root .. "/src/" .. top) ~= nil)
  elseif ext == "rs" then
    return spec:find "^crate::" ~= nil or spec:find "^super::" ~= nil or spec:find "^self::" ~= nil
  elseif ext == "dart" then
    return not spec:find "^dart:" and (spec:find "^%." ~= nil or not spec:find "^package:")
  end
  return true -- Java, Kotlin, C#, PHP...: packages are told apart by layer and frameworks are already detected separately
end

---@class DddType
---@field name string
---@field kind "class"|"interface"|"enum"
---@field first integer
---@field last integer
---@field head string
---@field has_id boolean

---@class DddFile
---@field rel string
---@field layer string?
---@field ext string
---@field test boolean
---@field imports { line: integer, spec: string, layer: string?, framework: string? }[]
---@field types DddType[]
---@field mtime integer
---@field size integer

---@class DddIndex
---@field root string
---@field files table<string, DddFile>
---@field list DddFile[]
---@field counts table<string, integer>  files per layer
---@field seen integer  source files found (only those in layers are analysed)

---@type table<string, table<string, DddFile>>
local cache = {}
---@type table<string, fun(index: DddIndex)[]>
local waiting = {}

---@param head string
---@return "class"|"interface"|"enum"
local function kind_of(head)
  if
    head:find "interface"
    or head:find "^%s*pub%s+trait"
    or head:find "^%s*trait"
    or head:find "protocol"
    or head:find "%(.*Protocol"
    or head:find "%(.*ABC"
  then
    return "interface"
  end
  if head:find "enum" then
    return "enum"
  end
  return "class"
end

---@param lines string[]
---@param decl AgentTypeDecl
---@return DddType
local function describe(lines, decl)
  local head = ""
  for i = decl.first, math.min(decl.last, decl.first + 4) do
    local l = lines[i] or ""
    if
      l:match "%S"
      and not l:match "^%s*//"
      and not l:match "^%s*#"
      and not l:match "^%s*%*"
      and not l:match "^%s*/%*"
    then
      head = vim.trim(l):sub(1, 120)
      break
    end
  end
  local has_id = false
  for i = decl.first, math.min(decl.last, decl.first + 60) do
    if (lines[i] or ""):find "%f[%w_][Ii][Dd]%f[^%w_]" then
      has_id = true
      break
    end
  end
  return { name = decl.name, kind = kind_of(head), first = decl.first, last = decl.last, head = head, has_id = has_id }
end

local lang_cache = {}

---@param path string
---@param ext string
---@return string?
local function lang_of(path, ext)
  if lang_cache[ext] == nil then
    local ft = vim.filetype.match { filename = path }
    lang_cache[ext] = ft and vim.treesitter.language.get_lang(ft) or false
  end
  return lang_cache[ext] or nil
end

---@param ctx DddCtx
---@param rel string
---@param prev DddFile?
---@return DddFile?
local function read_file(ctx, rel, prev)
  local root = ctx.root
  local path = root .. "/" .. rel
  local st = vim.uv.fs_stat(path)
  if not st or st.size > MAX_BYTES then
    return nil
  end
  if prev and prev.mtime == st.mtime.sec and prev.size == st.size then
    return prev
  end
  local ext = rel:match "%.([%w]+)$" or ""
  local lines = vim.fn.readfile(path)
  local file = {
    rel = rel,
    ext = ext,
    layer = layers.of(rel),
    test = layers.is_test(rel),
    imports = {},
    types = {},
    mtime = st.mtime.sec,
    size = st.size,
  }

  for _, imp in ipairs(imports.extract(lines, ext)) do
    imp.framework = imports.framework(imp.spec, ext)
    imp.layer = (not imp.framework and is_internal(imp.spec, ext, ctx)) and layers.of(imp.spec) or nil
    file.imports[#file.imports + 1] = imp
  end
  local lang = lang_of(path, ext)
  if lang then
    local ok, decls = pcall(scopes.type_declarations, table.concat(lines, "\n"), lang)
    for _, d in ipairs(ok and decls or {}) do
      if d.name and not d.kind:find("impl", 1, true) then
        file.types[#file.types + 1] = describe(lines, d)
      end
    end
  end
  return file
end

--- Source code paths of the project (names only: listing is cheap; reading and parsing is not)
---@param root string
---@return string[]
local function list_sources(root)
  local ignored = {}
  for _, name in ipairs(settings.ignore) do
    ignored[name] = true
  end
  local out = {}
  for rel, kind in
    vim.fs.dir(root, {
      depth = 12,
      skip = function(dir)
        return not ignored[dir]
      end,
    })
  do
    if kind == "file" and imports.supports(rel:match "%.([%w]+)$" or "") then
      out[#out + 1] = rel
      if #out >= settings.max_files * 5 then
        break
      end
    end
  end
  return out
end

--- Index of the project at `root` (from the cache if nothing changed); `cb` receives the index
---@param root string
---@param cb fun(index: DddIndex)
function M.get(root, cb)
  if waiting[root] then
    table.insert(waiting[root], cb)
    return
  end
  waiting[root] = { cb }
  local seen = list_sources(root)
  -- Only what the DDD rules look at is read and parsed: files INSIDE a layer that are not tests.
  -- In a large repo this is the difference between 10 s and a few milliseconds.
  local rels = {}
  for _, rel in ipairs(seen) do
    if layers.of(rel) and not layers.is_test(rel) and #rels < settings.max_files then
      rels[#rels + 1] = rel
    end
  end
  local previous = cache[root] or {}
  local ctx = { root = root }
  local gomod = vim.uv.fs_stat(root .. "/go.mod") and vim.fn.readfile(root .. "/go.mod")[1] or nil
  ctx.go_module = gomod and gomod:match "^module%s+(%S+)" or nil
  local files = {}
  local i = 0

  local function finish()
    cache[root] = files
    local list, counts = {}, {}
    for _, f in pairs(files) do
      list[#list + 1] = f
      if f.layer and not f.test then
        counts[f.layer] = (counts[f.layer] or 0) + 1
      end
    end
    table.sort(list, function(a, b)
      return a.rel < b.rel
    end)
    local index = { root = root, files = files, list = list, counts = counts, seen = #seen }
    local callbacks = waiting[root]
    waiting[root] = nil
    for _, f in ipairs(callbacks) do
      pcall(f, index)
    end
  end

  local function step()
    local stop = math.min(i + CHUNK, #rels)
    while i < stop do
      i = i + 1
      local ok, file = pcall(read_file, ctx, rels[i], previous[rels[i]])
      if ok and file then
        files[rels[i]] = file
      end
    end
    if i < #rels then
      vim.schedule(step)
    else
      finish()
    end
  end
  vim.schedule(step)
end

--- All types in the project with that name (case-insensitive)
---@param index DddIndex
---@param name string
---@return { file: DddFile, type: DddType }[]
function M.types_named(index, name)
  local out = {}
  for _, f in ipairs(index.list) do
    for _, t in ipairs(f.types) do
      if t.name:lower() == name:lower() then
        out[#out + 1] = { file = f, type = t }
      end
    end
  end
  return out
end

--- Forgets the cache (tests)
function M.reset()
  cache, waiting, lang_cache = {}, {}, {}
end

return M
