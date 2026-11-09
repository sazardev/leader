-- ── Shared C# code index (treesitter over text, no LSP or LLM) ────────────────
-- What the C# helpers need: read a file (namespaces, types, bases, members, attributes), a project (every .cs
-- under it, with the unsaved buffer in place of the one on disk) and what that project offers (interfaces and
-- the classes that implement them, entities with an Id, services). Everything is cached by modification time:
-- asking for the same file twice does not parse again, and a new keystroke in the current buffer invalidates only
-- that buffer.
local M = {}

M.MAX_FILES = 800
M.MAX_DEPTH = 15

local SKIP_DIRS = {
  ["bin"] = true,
  ["obj"] = true,
  [".git"] = true,
  [".vs"] = true,
  [".idea"] = true,
  ["node_modules"] = true,
  ["TestResults"] = true,
  ["publish"] = true,
  ["Migrations"] = true,
  -- Unity generated folders
  ["Library"] = true,
  ["Temp"] = true,
  ["Logs"] = true,
  ["UserSettings"] = true,
  ["Build"] = true,
  ["Builds"] = true,
}

local TYPE_KINDS = {
  class_declaration = "class",
  interface_declaration = "interface",
  record_declaration = "record",
  struct_declaration = "struct",
  enum_declaration = "enum",
}

local TYPE_NODES = {
  identifier = true,
  predefined_type = true,
  generic_name = true,
  qualified_name = true,
  nullable_type = true,
  array_type = true,
  tuple_type = true,
  pointer_type = true,
  implicit_type = true,
  ref_type = true,
  function_pointer_type = true,
}

local TEST_ATTRIBUTES = {
  Fact = true,
  Theory = true,
  Test = true,
  TestCase = true,
  TestMethod = true,
  DataTestMethod = true,
}

---@param path string
---@return string?
local function read(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local text = f:read "*a"
  f:close()
  return text
end

---@param n TSNode
---@param src string
---@return string
local function text(n, src)
  return n and vim.treesitter.get_node_text(n, src) or ""
end

---@param n TSNode
---@param src string
---@return string?
local function name_of(n, src)
  local f = n:field("name")[1]
  if f then
    return text(f, src)
  end
  for c in n:iter_children() do
    if c:type() == "identifier" then
      return text(c, src)
    end
  end
end

---@param n TSNode
---@param src string
---@return string[]
local function modifiers(n, src)
  local out = {}
  for c in n:iter_children() do
    if c:type() == "modifier" then
      out[#out + 1] = text(c, src)
    end
  end
  return out
end

---@param list string[]
---@param word string
---@return boolean
local function has(list, word)
  return vim.tbl_contains(list, word)
end

--- The names inside an attribute list (`[Fact]`, `[xunit.Fact]`, `[FactAttribute]`)
---@param n TSNode
---@param src string
---@return string[]
local function attributes(n, src)
  local out = {}
  for c in n:iter_children() do
    if c:type() == "attribute_list" then
      for a in c:iter_children() do
        if a:type() == "attribute" then
          local name = name_of(a, src) or text(a, src):match "^([%w_%.]+)"
          if name and name ~= "" then
            out[#out + 1] = name
          end
        end
      end
    end
  end
  return out
end

--- `Fact`, `xunit.Fact`, `FactAttribute` → `Fact`
---@param raw string
---@return string
function M.attribute_name(raw)
  local name = raw:match "([%w_]+)$" or raw
  return (name:gsub("Attribute$", ""))
end

---@param attrs string[]
---@param wanted string
---@return boolean
function M.has_attribute(attrs, wanted)
  for _, a in ipairs(attrs) do
    if M.attribute_name(a) == wanted then
      return true
    end
  end
  return false
end

---@param attrs string[]
---@return boolean
function M.is_test(attrs)
  for _, a in ipairs(attrs) do
    if TEST_ATTRIBUTES[M.attribute_name(a)] then
      return true
    end
  end
  return false
end

--- The type node of a declaration (return type, property type, field type)
---@param n TSNode
---@param name_node TSNode?
---@param src string
---@return string?
local function type_of(n, name_node, src)
  local field = n:field("type")[1]
  if field then
    return text(field, src)
  end
  local found
  for c in n:iter_children() do
    if c == name_node then
      break
    end
    if c:named() and TYPE_NODES[c:type()] then
      found = c
    end
  end
  return found and text(found, src) or nil
end

---@class CSharpParam
---@field name string?
---@field type string?

---@param node TSNode?
---@param src string
---@return CSharpParam[]
local function parameters(node, src)
  local list
  if node and node:type() == "parameter_list" then
    list = node
  elseif node then
    list = node:field("parameters")[1] or node:field("parameter_list")[1]
    if not list then
      for c in node:iter_children() do
        if c:type() == "parameter_list" then
          list = c
          break
        end
      end
    end
  end
  if not list then
    return {}
  end
  local out = {}
  for c in list:iter_children() do
    if c:type() == "parameter" then
      out[#out + 1] = { name = name_of(c, src), type = type_of(c, nil, src) }
    end
  end
  return out
end

---@class CSharpMember
---@field kind "method"|"constructor"|"property"|"field"|"event"
---@field name string
---@field type string?
---@field params CSharpParam[]
---@field attributes string[]
---@field modifiers string[]
---@field line integer
---@field last integer
---@field initialized boolean?
---@field readonly boolean?
---@field static boolean?
---@field test boolean?

---@param info table
---@param node TSNode
---@param src string
local function add_member(info, node, src)
  local t = node:type()
  local attrs = attributes(node, src)
  local mods = modifiers(node, src)
  local first, _, last = node:range()
  local line, finish = first + 1, last + 1
  local member = {
    attributes = attrs,
    modifiers = mods,
    line = line,
    last = finish,
    params = {},
    static = has(mods, "static"),
    readonly = has(mods, "readonly"),
  }
  if t == "method_declaration" then
    local name_node = node:field("name")[1]
    member.kind = "method"
    member.name = name_of(node, src) or ""
    member.type = type_of(node, name_node, src)
    member.params = parameters(node, src)
    member.test = M.is_test(attrs)
    info.methods[#info.methods + 1] = member
    info.members[#info.members + 1] = member
  elseif t == "constructor_declaration" then
    member.kind = "constructor"
    member.name = name_of(node, src) or ""
    member.params = parameters(node, src)
    info.ctors[#info.ctors + 1] = member
    info.members[#info.members + 1] = member
  elseif t == "property_declaration" then
    member.kind = "property"
    member.name = name_of(node, src) or ""
    member.type = type_of(node, node:field("name")[1], src)
    info.properties[#info.properties + 1] = member
    info.members[#info.members + 1] = member
  elseif t == "field_declaration" or t == "event_field_declaration" then
    local decl
    for c in node:iter_children() do
      if c:type() == "variable_declaration" then
        decl = c
        break
      end
    end
    local ty = decl and decl:field("type")[1] or nil
    for c in (decl or node):iter_children() do
      if c:type() == "variable_declarator" then
        local name = name_of(c, src)
        if name then
          local copy = vim.deepcopy(member)
          copy.kind = t == "event_field_declaration" and "event" or "field"
          copy.name = name
          copy.type = ty and text(ty, src) or nil
          copy.initialized = text(c, src):find("=", 1, true) ~= nil
          info.fields[#info.fields + 1] = copy
          info.members[#info.members + 1] = copy
        end
      end
    end
  end
end

---@class CSharpType
---@field name string
---@field kind "class"|"interface"|"record"|"struct"|"enum"
---@field namespace string?
---@field full_name string
---@field bases string[]
---@field base_names string[]
---@field attributes string[]
---@field modifiers string[]
---@field generic boolean?
---@field members CSharpMember[]
---@field methods CSharpMember[]
---@field properties CSharpMember[]
---@field fields CSharpMember[]
---@field ctors CSharpMember[]
---@field primary CSharpParam[]
---@field line integer
---@field last integer
---@field file string?
---@field has_id boolean?
---@field id_type string?
---@field test_methods CSharpMember[]
---@field interfaces string[]

---@param info table
---@param node TSNode
---@param ns string?
---@param stack string[]
---@param src string
local function add_type(info, node, ns, stack, src)
  local kind = TYPE_KINDS[node:type()]
  local name = name_of(node, src)
  if not kind or not name then
    return
  end
  if kind == "record" and text(node, src):match "^%s*record%s+struct" then
    kind = "struct"
  end
  local first, _, last = node:range()
  local full = table.concat(vim.list_extend(vim.deepcopy(stack), { name }), ".")
  local type_info = {
    name = name,
    kind = kind,
    namespace = ns,
    full_name = ns and (ns .. "." .. full) or full,
    bases = {},
    base_names = {},
    attributes = attributes(node, src),
    modifiers = modifiers(node, src),
    members = {},
    methods = {},
    properties = {},
    fields = {},
    ctors = {},
    primary = {},
    line = first + 1,
    last = last + 1,
    test_methods = {},
    interfaces = {},
  }
  type_info.is_public = has(type_info.modifiers, "public") or not has(type_info.modifiers, "private")
  type_info.is_abstract = has(type_info.modifiers, "abstract")
  type_info.is_static = has(type_info.modifiers, "static")
  type_info.is_sealed = has(type_info.modifiers, "sealed")
  type_info.generic = false
  for c in node:iter_children() do
    if c:type() == "type_parameter_list" then
      type_info.generic = true
    elseif c:type() == "base_list" then
      for b in c:iter_children() do
        if b:named() and b:type() ~= "argument_list" then
          local raw = text(b, src):gsub("%s*%(.*$", "")
          if raw ~= "" and not vim.tbl_contains(type_info.bases, raw) then
            type_info.bases[#type_info.bases + 1] = raw
            type_info.base_names[#type_info.base_names + 1] = raw:gsub("<.*$", "")
          end
        end
      end
    elseif c:type() == "parameter_list" then
      type_info.primary = parameters(c, src)
    end
  end
  for _, base in ipairs(type_info.base_names) do
    if base:match "^I%u" then
      type_info.interfaces[#type_info.interfaces + 1] = base
    end
  end
  info.types[#info.types + 1] = type_info
  local body = node:field("body")[1]
  if body then
    for c in body:iter_children() do
      if c:named() then
        if TYPE_KINDS[c:type()] then
          add_type(info, c, ns, vim.list_extend(vim.deepcopy(stack), { name }), src)
        else
          add_member(type_info, c, src)
        end
      end
    end
  end
  for _, m in ipairs(type_info.methods) do
    if m.test then
      type_info.test_methods[#type_info.test_methods + 1] = m
    end
  end
  for _, f in ipairs(type_info.fields) do
    if f.name:lower() == "id" and f.type then
      type_info.has_id = true
      type_info.id_type = f.type
      break
    end
  end
  if not type_info.has_id then
    for _, p in ipairs(type_info.properties) do
      if p.name:lower() == "id" and p.type then
        type_info.has_id = true
        type_info.id_type = p.type
        break
      end
    end
  end
  if not type_info.has_id then
    for _, p in ipairs(type_info.primary) do
      if p.name and p.name:lower() == "id" and p.type then
        type_info.has_id = true
        type_info.id_type = p.type
        break
      end
    end
  end
end

--- Parse one C# source string
---@param src string
---@return { namespace: string?, usings: string[], types: CSharpType[] }
function M.scan(src)
  local info = { namespace = nil, usings = {}, types = {} }
  local ok, parser = pcall(vim.treesitter.get_string_parser, src, "c_sharp")
  if not ok or not parser then
    return info
  end
  local ok_tree, trees = pcall(function()
    return parser:parse()
  end)
  local root = ok_tree and trees and trees[1] and trees[1]:root() or nil
  if not root then
    return info
  end

  local function qualify(ns, name)
    if not name or name == "" then
      return ns
    end
    return ns and (ns .. "." .. name) or name
  end

  local function add_using(node)
    local raw = text(node, src)
    local name = raw:match "^%s*using%s+static%s+([%w_%.]+)" or raw:match "^%s*using%s+([%w_%.]+)%s*;"
    if name then
      info.usings[#info.usings + 1] = name
    end
  end

  local function walk(node, ns, stack)
    local file_ns = ns
    for c in node:iter_children() do
      local t = c:type()
      if t == "file_scoped_namespace_declaration" then
        file_ns = qualify(ns, name_of(c, src))
        info.namespace = info.namespace or file_ns
      elseif t == "namespace_declaration" then
        local child_ns = qualify(file_ns, name_of(c, src))
        info.namespace = info.namespace or child_ns
        walk(c, child_ns, stack)
      elseif t == "using_directive" then
        add_using(c)
      elseif TYPE_KINDS[t] then
        add_type(info, c, file_ns, stack, src)
      elseif c:named() then
        walk(c, file_ns, stack)
      end
    end
  end

  walk(root, nil, {})
  return info
end

local buffer_cache = {}

--- Parse a buffer (cached by changedtick)
---@param buf integer
---@return { namespace: string?, usings: string[], types: CSharpType[], file: string }
function M.scan_buffer(buf)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  local tick = vim.b[buf].changedtick or 0
  local key = buf .. ":" .. tick
  if buffer_cache[key] then
    return buffer_cache[key]
  end
  local stale = {}
  for k in pairs(buffer_cache) do
    if vim.startswith(k, buf .. ":") and k ~= key then
      stale[#stale + 1] = k
    end
  end
  for _, k in ipairs(stale) do
    buffer_cache[k] = nil
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local info = M.scan(table.concat(lines, "\n"))
  info.file = vim.api.nvim_buf_get_name(buf)
  for _, t in ipairs(info.types) do
    t.file = info.file
  end
  buffer_cache[key] = info
  return info
end

local file_cache = {}

--- Parse a file (cached by mtime and size)
---@param path string
---@return { namespace: string?, usings: string[], types: CSharpType[], file: string }?
function M.file(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return nil
  end
  local stamp = ("%d:%d:%d"):format(stat.mtime.sec, stat.mtime.nsec, stat.size)
  local entry = file_cache[path]
  if entry and entry.stamp == stamp then
    return entry.info
  end
  local src = read(path)
  if not src then
    return nil
  end
  local info = M.scan(src)
  info.file = path
  for _, t in ipairs(info.types) do
    t.file = path
  end
  file_cache[path] = { stamp = stamp, info = info }
  return info
end

local dir_cache = {}
local DIR_TTL = 5000 -- ms

---@param root string
---@return string[]
local function files(root)
  local now = vim.uv.now()
  local entry = dir_cache[root]
  if entry and now - entry.at < DIR_TTL then
    return entry.files
  end
  local out = {}
  local function walk(dir, depth)
    if #out >= M.MAX_FILES or depth > M.MAX_DEPTH then
      return
    end
    local ok, iter = pcall(vim.fs.dir, dir)
    if not ok then
      return
    end
    for name, kind in iter do
      local path = dir .. "/" .. name
      if kind == "directory" then
        if not SKIP_DIRS[name] and name:sub(1, 1) ~= "." then
          walk(path, depth + 1)
        end
      elseif kind == "file" and name:match "%.cs$" then
        if not (name:match "%.g%.cs$" or name:match "%.Designer%.cs$" or name:match "AssemblyInfo%.cs$") then
          out[#out + 1] = path
        end
      end
    end
  end
  walk(root, 0)
  table.sort(out)
  dir_cache[root] = { at = now, files = out }
  return out
end

---@class CSharpProject
---@field root string
---@field types CSharpType[]
---@field interfaces CSharpType[]
---@field classes CSharpType[]
---@field by_name table<string, CSharpType>
---@field by_full table<string, CSharpType>
---@field implementations table<string, CSharpType[]>
---@field entities CSharpType[]
---@field services CSharpType[]

local NOT_ENTITY = {
  "DbContext$",
  "Service$",
  "Repository$",
  "Controller$",
  "Endpoint$",
  "Request$",
  "Response$",
  "Dto$",
  "Options$",
  "Program$",
  "Startup$",
  "Test$",
  "Tests$",
  "Exception$",
  "Mapping$",
  "Profile$",
  "Extensions$",
}

local NOT_SERVICE = {
  "Controller$",
  "Endpoint$",
  "Dto$",
  "Request$",
  "Response$",
  "Options$",
  "Entity$",
  "Model$",
  "DbContext$",
  "Program$",
  "Startup$",
  "Test$",
  "Tests$",
  "Exception$",
  "Mapping$",
  "Profile$",
}

local SERVICE_NAME =
  "Service$|Repository$|Handler$|Provider$|Factory$|Validator$|Client$|Store$|Manager$|Bus$|Publisher$|Consumer$|UseCase$|Gateway$|Adapter$|Processor$|Worker$"

---@param name string
---@param patterns string[]
---@return boolean
local function excluded(name, patterns)
  for _, p in ipairs(patterns) do
    if name:match(p) then
      return true
    end
  end
  return false
end

--- Index of a project: every .cs under `root` (the live buffer replaces its file)
---@param root string
---@param live { path: string, text: string }?
---@return CSharpProject
function M.project(root, live)
  local project = {
    root = root,
    types = {},
    interfaces = {},
    classes = {},
    by_name = {},
    by_full = {},
    implementations = {},
    entities = {},
    services = {},
  }
  local function add(info)
    if not info then
      return
    end
    for _, t in ipairs(info.types) do
      project.types[#project.types + 1] = t
      project.by_name[t.name] = project.by_name[t.name] or t
      project.by_full[t.full_name] = project.by_full[t.full_name] or t
      if t.kind == "interface" then
        project.interfaces[#project.interfaces + 1] = t
      elseif t.kind == "class" or t.kind == "record" or t.kind == "struct" then
        project.classes[#project.classes + 1] = t
      end
    end
  end
  for _, path in ipairs(files(root)) do
    if live and live.path == path then
      local info = M.scan(live.text)
      info.file = path
      for _, t in ipairs(info.types) do
        t.file = path
      end
      add(info)
    else
      add(M.file(path))
    end
  end
  if live and not vim.tbl_contains(files(root), live.path) then
    local info = M.scan(live.text)
    info.file = live.path
    for _, t in ipairs(info.types) do
      t.file = live.path
    end
    add(info)
  end
  for _, t in ipairs(project.classes) do
    for _, base in ipairs(t.bases) do
      local short = base:gsub("<.*$", "")
      project.implementations[base] = project.implementations[base] or {}
      table.insert(project.implementations[base], t)
      project.implementations[short] = project.implementations[short] or {}
      table.insert(project.implementations[short], t)
    end
  end
  for _, t in ipairs(project.classes) do
    if t.has_id and not t.is_abstract and not t.is_static and not t.generic and not excluded(t.name, NOT_ENTITY) then
      project.entities[#project.entities + 1] = t
    end
    if
      not t.is_abstract
      and not t.is_static
      and not t.generic
      and t.is_public
      and not excluded(t.name, NOT_SERVICE)
      and (#t.interfaces > 0 or t.name:match(SERVICE_NAME) ~= nil)
    then
      project.services[#project.services + 1] = t
    end
  end
  return project
end

--- Forget the directory listing and one file (after `dotnet` changed the project)
---@param root string
---@param path string?
function M.invalidate(root, path)
  dir_cache[root] = nil
  if path then
    file_cache[path] = nil
  end
end

--- The innermost type whose lines hold `row`
---@param info { types: CSharpType[] }
---@param row integer
---@return CSharpType?
function M.type_at(info, row)
  local best
  for _, t in ipairs(info.types or {}) do
    if row >= t.line and row <= t.last and (not best or t.line >= best.line) then
      best = t
    end
  end
  return best
end

return M
