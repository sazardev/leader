-- ── Shared Go code index (treesitter over text, no LSP or LLM) ───────────────
-- What this config's Go helpers need (goimpl, goiferr, gomap, gowire, goenum, goport, gohttp):
-- read a file (interfaces, structs, methods, functions, constants, imports), a package (all its
-- files, with the unsaved buffer in place of the one on disk) and the module (go.mod paths → directories).
-- Everything is cached by modification time: asking for the same thing twice doesn't parse again.
local M = {}

local BUILTIN = {}
for _, n in ipairs {
  "any",
  "bool",
  "byte",
  "comparable",
  "complex64",
  "complex128",
  "error",
  "float32",
  "float64",
  "int",
  "int8",
  "int16",
  "int32",
  "int64",
  "rune",
  "string",
  "uint",
  "uint8",
  "uint16",
  "uint32",
  "uint64",
  "uintptr",
} do -- stylua: ignore
  BUILTIN[n] = true
end

local KEYWORDS = {}
for _, kw in ipairs {
  "break",
  "case",
  "chan",
  "const",
  "continue",
  "default",
  "defer",
  "else",
  "fallthrough",
  "for",
  "func",
  "go",
  "goto",
  "if",
  "import",
  "interface",
  "map",
  "package",
  "range",
  "return",
  "select",
  "struct",
  "switch",
  "type",
  "var",
} do -- stylua: ignore
  KEYWORDS[kw] = true
end

-- ── reading a file (treesitter over text) ─────────────────────────────────────

---@class GoImplMethod
---@field name string
---@field sig string        `(ctx context.Context, id string) (*Note, error)` exactly as in the interface
---@field refs { pos: integer, name: string }[] unqualified types inside `sig` (qualified when the interface is used from another package)
---@field params { name: string?, type: string }[]
---@field results string[]
---@field named boolean     all parameters have names

---@class GoImplFile
---@field pkg string?
---@field imports table<string, string> alias → import path
---@field interfaces table<string, GoImplMethod[]>
---@field structs table<string, { name: string, type: string }[]>
---@field types table<string, string> defined types that are neither struct nor interface (`Kind` → `string`)
---@field methods { recv: string, name: string, ptr: boolean, var: string? }[]
---@field ctors { result: string, builds: table<string, boolean> }[]
---@field asserts { iface: string, typ: string }[]
---@field funcs GoImplMethod[]  top-level functions (with signature)
---@field consts { name: string, type: string?, lit: string?, iota: integer }[]

---@param n TSNode
---@param src string
local function text(n, src)
  return vim.treesitter.get_node_text(n, src)
end

--- Unqualified local types inside `n` (byte position relative to the start of `n`)
---@param n TSNode
---@param src string
---@return { pos: integer, name: string }[]
local function local_type_refs(n, src)
  local _, _, base = n:range(true)
  local refs = {}
  local function walk(node)
    if node:type() == "type_identifier" then
      local parent = node:parent()
      local name = text(node, src)
      if not (parent and parent:type() == "qualified_type") and not BUILTIN[name] then
        local _, _, byte = node:range(true)
        refs[#refs + 1] = { pos = byte - base, name = name }
      end
    end
    for child in node:iter_children() do
      walk(child)
    end
  end
  walk(n)
  return refs
end

--- parameter_list → flat list { name?, type } (one element per name) and whether all have names
---@param list TSNode?
---@param src string
---@return { name: string?, type: string }[], boolean
local function flat_params(list, src)
  local out, named = {}, true
  if not list then
    return out, named
  end
  for decl in list:iter_children() do
    local t = decl:type()
    if t == "parameter_declaration" or t == "variadic_parameter_declaration" then
      local ty = decl:field("type")[1]
      local ty_text = ty and text(ty, src) or ""
      if t == "variadic_parameter_declaration" then
        ty_text = "..." .. ty_text
      end
      local names = decl:field "name"
      if #names == 0 then
        named = false
        out[#out + 1] = { type = ty_text }
      else
        for _, name in ipairs(names) do
          out[#out + 1] = { name = text(name, src), type = ty_text }
        end
      end
    end
  end
  return out, named
end

--- Signature of a method (of an interface or declared): text as-is, unqualified local types, parameters and returns
---@param whole TSNode method_elem | method_declaration
---@param name TSNode
---@param params TSNode
---@param result TSNode?
---@param src string
---@return GoImplMethod
local function method_data(whole, name, params, result, src)
  local last = result or params
  local _, _, first_byte = params:range(true)
  local _, _, _, _, _, last_byte = last:range(true)
  local sig = src:sub(first_byte + 1, last_byte)
  local _, _, whole_byte = whole:range(true)
  local refs = {}
  for _, r in ipairs(local_type_refs(whole, src)) do
    local pos = r.pos + whole_byte - first_byte -- position inside `sig` (parameter names don't count)
    if pos >= 0 and pos < #sig then
      refs[#refs + 1] = { pos = pos, name = r.name }
    end
  end
  local plist, named = flat_params(params, src)
  local results = {}
  if result then
    if result:type() == "parameter_list" then
      for _, p in ipairs((flat_params(result, src))) do
        results[#results + 1] = p.type
      end
    else
      results[1] = text(result, src)
    end
  end
  return { name = text(name, src), sig = sig, refs = refs, params = plist, results = results, named = named }
end

---@param spec_type TSNode interface_type
---@param src string
---@return GoImplMethod[]
local function interface_methods(spec_type, src)
  local methods = {}
  for elem in spec_type:iter_children() do
    if elem:type() == "method_elem" then
      local name, params, result = elem:field("name")[1], elem:field("parameters")[1], elem:field("result")[1]
      if name and params then
        methods[#methods + 1] = method_data(elem, name, params, result, src)
      end
    end
  end
  return methods
end

---@param src string
---@return GoImplFile?
local function scan(src)
  local ok, parser = pcall(vim.treesitter.get_string_parser, src, "go")
  if not ok then
    return nil
  end
  local root = parser:parse()[1]:root()
  ---@type GoImplFile
  local info = {
    imports = {},
    interfaces = {},
    structs = {},
    types = {},
    methods = {},
    ctors = {},
    asserts = {},
    funcs = {},
    consts = {},
  }

  local function imports(node)
    for child in node:iter_children() do
      if child:type() == "import_spec" then
        local path = child:field("path")[1]
        local alias = child:field("name")[1]
        if path then
          local p = text(path, src):gsub('^["`]', ""):gsub('["`]$', "")
          info.imports[alias and text(alias, src) or p:match "([^/]+)$"] = p
        end
      elseif child:named() then
        imports(child)
      end
    end
  end

  for node in root:iter_children() do
    local t = node:type()
    if t == "package_clause" and node:named_child(0) then
      info.pkg = text(node:named_child(0), src)
    elseif t == "import_declaration" then
      imports(node)
    elseif t == "type_declaration" then
      for spec in node:iter_children() do
        local name, ty = spec:field("name")[1], spec:field("type")[1]
        if spec:type() == "type_spec" and name and ty then
          local n = text(name, src)
          if ty:type() == "interface_type" then
            info.interfaces[n] = interface_methods(ty, src)
          elseif ty:type() == "struct_type" then
            local fields = {}
            for _, list in ipairs(ty:named_children()) do
              for _, field in ipairs(list:named_children()) do
                local ft = field:field("type")[1]
                if field:type() == "field_declaration" and ft then
                  for _, fname in ipairs(field:field "name") do
                    fields[#fields + 1] = { name = text(fname, src), type = text(ft, src) }
                  end
                end
              end
            end
            info.structs[n] = fields
          else
            info.types[n] = text(ty, src)
          end
        end
      end
    elseif t == "method_declaration" then
      local recv = node:field("receiver")[1]
      local name = node:field("name")[1]
      local decl = recv and recv:named_child(0)
      local ty = decl and decl:field("type")[1]
      if ty and name then
        local ptr = ty:type() == "pointer_type"
        local base = ptr and ty:named_child(0) or ty
        local var = decl:field("name")[1]
        local entry = { recv = text(base, src), name = text(name, src), ptr = ptr, var = var and text(var, src) or nil }
        local params = node:field("parameters")[1]
        if params then
          local data = method_data(node, name, params, node:field("result")[1], src)
          entry.sig, entry.refs, entry.params, entry.results, entry.named =
            data.sig, data.refs, data.params, data.results, data.named
        end
        info.methods[#info.methods + 1] = entry
      end
    elseif t == "function_declaration" then
      local fname, fparams = node:field("name")[1], node:field("parameters")[1]
      if fname and fparams then
        local data = method_data(node, fname, fparams, node:field("result")[1], src)
        info.funcs[#info.funcs + 1] = data
      end
      local result, body = node:field("result")[1], node:field("body")[1]
      if result and body and (result:type() == "type_identifier" or result:type() == "qualified_type") then
        local builds = {}
        for built in text(body, src):gmatch "&%s*([%a_][%w_]*)%s*{" do
          builds[built] = true
        end
        for built in text(body, src):gmatch "return%s+([%a_][%w_]*)%s*{" do
          builds[built] = true
        end
        info.ctors[#info.ctors + 1] = { result = text(result, src), builds = builds }
      end
    elseif t == "const_declaration" then
      -- a block with iota repeats the type and expression in the specs without a value
      local last_type, index = nil, 0
      for spec in node:iter_children() do
        if spec:type() == "const_spec" then
          local ty, value = spec:field("type")[1], spec:field("value")[1]
          if ty then
            last_type = text(ty, src)
          end
          local lit = value and text(value, src):match '^"(.*)"$' or nil
          for _, name in ipairs(spec:field "name") do
            info.consts[#info.consts + 1] = { name = text(name, src), type = last_type, lit = lit, iota = index }
          end
          index = index + 1
        end
      end
    elseif t == "var_declaration" then
      local body = text(node, src)
      local iface = body:match "var%s+_%s+([%w_%.]+)%s*="
      local typ = body:match "%(%*([%a_][%w_]*)%)%(nil%)" or body:match "&([%a_][%w_]*)%s*{"
      if iface and typ then
        info.asserts[#info.asserts + 1] = { iface = iface, typ = typ }
      end
    end
  end
  return info
end

-- ── index of a package (the directory's files, cached by date) ───────────────

local cache = {}

---@param path string
---@return GoImplFile?
local function file_info(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return nil
  end
  local stamp = ("%d.%d"):format(stat.mtime.sec, stat.mtime.nsec)
  local entry = cache[path]
  if not entry or entry.stamp ~= stamp then
    local f = io.open(path, "r")
    local src = f and f:read "*a"
    if f then
      f:close()
    end
    entry = { stamp = stamp, info = src and scan(src) or nil }
    cache[path] = entry
  end
  return entry.info
end

---@class GoImplPackage
---@field dir string
---@field name string?
---@field interfaces table<string, GoImplMethod[]>
---@field structs table<string, { name: string, type: string }[]>
---@field types table<string, string>
---@field methods { recv: string, name: string, ptr: boolean, var: string? }[]
---@field ctors { result: string, builds: table<string, boolean> }[]
---@field asserts { iface: string, typ: string }[]
---@field funcs GoImplMethod[]
---@field consts { name: string, type: string?, lit: string?, iota: integer }[]
---@field imports table<string, string>

--- Package of a directory. `live` = { path, text } replaces its file on disk (the unsaved buffer)
---@param dir string
---@param live { path: string, text: string }?
---@return GoImplPackage
local function package_at(dir, live)
  ---@type GoImplPackage
  local pkg = {
    dir = dir,
    interfaces = {},
    structs = {},
    types = {},
    methods = {},
    ctors = {},
    asserts = {},
    imports = {},
    funcs = {},
    consts = {},
  }
  local function add(info)
    if not info then
      return
    end
    pkg.name = pkg.name or info.pkg
    for k, v in pairs(info.interfaces) do
      pkg.interfaces[k] = v
    end
    for k, v in pairs(info.structs) do
      pkg.structs[k] = v
    end
    for k, v in pairs(info.types) do
      pkg.types[k] = v
    end
    vim.list_extend(pkg.methods, info.methods)
    vim.list_extend(pkg.ctors, info.ctors)
    vim.list_extend(pkg.asserts, info.asserts)
    vim.list_extend(pkg.funcs, info.funcs)
    vim.list_extend(pkg.consts, info.consts)
    for k, v in pairs(info.imports) do
      pkg.imports[k] = pkg.imports[k] or v
    end
  end
  local seen = 0
  for name, kind in vim.fs.dir(dir) do
    local path = dir .. "/" .. name
    if kind == "file" and name:match "%.go$" and not name:match "_test%.go$" and seen < 300 then
      seen = seen + 1
      if not (live and live.path == path) then
        add(file_info(path))
      end
    end
  end
  if live then
    add(scan(live.text))
  end
  return pkg
end

--- Directory of an import that belongs to the module (`notesapi/internal/domain` → <root>/internal/domain)
---@param import_path string
---@param from string file from which it is imported
---@return string?
local function module_dir(import_path, from)
  local gomod = vim.fs.find("go.mod", { path = vim.fs.dirname(from), upward = true })[1]
  if not gomod then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, gomod)
  local module = ok and table.concat(lines, "\n"):match "module%s+([^%s]+)"
  if not module then
    return nil
  end
  local root = vim.fs.dirname(gomod)
  if import_path == module then
    return root
  end
  if import_path:sub(1, #module + 1) == module .. "/" then
    return root .. "/" .. import_path:sub(#module + 2)
  end
end

-- ── the whole module (to look up constructors, structs and interfaces by name) ──

local SKIP_DIRS = { vendor = true, node_modules = true, testdata = true, [".git"] = true }
local MODULE_FILES_MAX = 800
local MODULE_TTL = 5 -- seconds between tree listings (each file's content is checked by date)
local module_cache = {}

---@class GoImplModule
---@field root string
---@field module string
---@field packages GoImplPackage[]  with `import_path`

--- Root and name of the go.mod module that contains `from`
---@param from string
---@return string? root, string? module
local function module_of(from)
  local gomod = vim.fs.find("go.mod", { path = vim.fs.dirname(from), upward = true })[1]
  if not gomod then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, gomod)
  local module = ok and table.concat(lines, "\n"):match "module%s+([^%s]+)"
  return module and vim.fs.dirname(gomod) or nil, module
end

--- All the packages of `from`'s module (excluding tests, vendor and testdata), with their import path
---@param from string
---@return GoImplModule?
local function module_packages(from)
  local root, module = module_of(from)
  if not root then
    return nil
  end
  local entry = module_cache[root]
  if entry and os.time() - entry.at < MODULE_TTL then
    return entry.value
  end
  local dirs, count = {}, 0
  for rel, kind in
    vim.fs.dir(root, {
      depth = 8,
      skip = function(name)
        return not SKIP_DIRS[name]
      end,
    })
  do
    if kind == "file" and rel:match "%.go$" and not rel:match "_test%.go$" and count < MODULE_FILES_MAX then
      count = count + 1
      local dir = vim.fs.dirname(rel)
      dirs[dir] = true
    end
  end
  local packages = {}
  for dir in pairs(dirs) do
    local abs = dir == "." and root or (root .. "/" .. dir)
    local pkg = package_at(abs)
    pkg.import_path = dir == "." and module or (module .. "/" .. dir)
    packages[#packages + 1] = pkg
  end
  table.sort(packages, function(a, b)
    return a.dir < b.dir
  end)
  local value = { root = root, module = module, packages = packages }
  module_cache[root] = { at = os.time(), value = value }
  return value
end

--- Directory of the package written as `alias.` in a file: through its import or, if that file doesn't import it
--- (the interface was declared in another file with other imports), through the package name among the module's
---@param alias string
---@param pkg GoImplPackage
---@param file_path string
---@return string?
local function dir_for(alias, pkg, file_path)
  local import_path = pkg.imports[alias]
  if import_path then
    return module_dir(import_path, file_path)
  end
  local module = module_packages(file_path)
  for _, p in ipairs(module and module.packages or {}) do
    if p.name == alias and p.dir ~= pkg.dir then
      return p.dir
    end
  end
end

---@param a string
---@param b string
---@return boolean
local function related(a, b)
  a, b = a:lower(), b:lower()
  if a == b then
    return true
  end
  -- the longer name ENDS in the shorter one (noteService ~ NoteService, postgresNoteRepository ~ NoteRepository) or is
  -- `<short>Impl`; containing it or starting the same isn't enough (Note doesn't implement NoteRepository). The short one, 4+ letters
  local short, long = #a < #b and a or b, #a < #b and b or a
  if #short < 4 then
    return false
  end
  return long:sub(-#short) == short or long == short .. "impl"
end

---@param name string
---@return string
local function lower_first(name)
  local r = name:sub(1, 1):lower()
  return KEYWORDS[r] and r .. "_" or r
end

--- Interface (with its methods) from how it is written; one from another package is read from disk
---@param written string `NoteService` | `domain.NoteRepository`
---@param pkg GoImplPackage
---@param file_path string
---@return GoImplMethod[]?, string? alias, table<string, boolean>? declared
local function resolve_interface(written, pkg, file_path)
  local alias, name = written:match "^([%w_]+)%.([%w_]+)$"
  if not alias then
    return pkg.interfaces[written]
  end
  local dir = dir_for(alias, pkg, file_path)
  if not dir or dir == pkg.dir then
    return nil
  end
  local other = package_at(dir)
  local declared = {}
  for n in pairs(other.interfaces) do
    declared[n] = true
  end
  for n in pairs(other.structs) do
    declared[n] = true
  end
  for n in pairs(other.types) do
    declared[n] = true
  end
  return other.interfaces[name], alias, declared
end

---@param pkg GoImplPackage
---@param struct string
---@return table<string, boolean>
local function defined_methods(pkg, struct)
  local set = {}
  for _, m in ipairs(pkg.methods) do
    if m.recv == struct then
      set[m.name] = true
    end
  end
  return set
end

---@param t string
---@return string
local function normalize(t)
  return (t:gsub("[%w_]+%.", ""))
end

---@param t string
---@param known table<string, string>
---@param structs table<string, any>
---@return string
local function zero_value(t, known, structs)
  if
    t == "error"
    or t:match "^[%*%[]"
    or t:match "^map%["
    or t:match "^chan%s"
    or t:match "^func"
    or t == "any"
    or t:match "^interface"
  then
    return "nil"
  elseif t == "string" then
    return '""'
  elseif t == "bool" then
    return "false"
  elseif t:match "^u?int%d*$" or t:match "^float%d+$" or t == "byte" or t == "rune" or t == "uintptr" then
    return "0"
  end
  local bare = normalize(t)
  if structs[bare] then
    return t .. "{}"
  elseif known[bare] then
    return zero_value(known[bare], {}, {})
  end
  return "*new(" .. t .. ")"
end

local function esc(s)
  return (s:gsub("[$}\\]", "\\%0"))
end

---@param row integer
---@param from integer column where what is replaced starts
---@param col integer
local function range_of(row, from, col)
  return { start = { line = row - 1, character = from }, ["end"] = { line = row - 1, character = col } }
end

---@return string path, string text
local function buffer_state()
  return vim.api.nvim_buf_get_name(0), table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

---@return GoImplPackage?, string path
local function current_package()
  local path, src = buffer_state()
  if path == "" then
    return nil, path
  end
  return package_at(vim.fs.dirname(path), { path = path, text = src }), path
end

--- Zero value of a type as written in the current file: resolves the package's structs, interfaces and defined
--- types and those of the imported module packages (`domain.Note` → `domain.Note{}`)
---@param t string
---@param pkg GoImplPackage
---@param file_path string
---@return string
local function zero_for(t, pkg, file_path)
  local alias, name = t:match "^([%w_]+)%.([%w_]+)$"
  if not alias then
    return pkg.interfaces[t] and "nil" or zero_value(t, pkg.types, pkg.structs)
  end
  local dir = dir_for(alias, pkg, file_path)
  if dir then
    local other = package_at(dir)
    if other.structs[name] then
      return t .. "{}"
    elseif other.interfaces[name] then
      return "nil"
    elseif other.types[name] then
      return zero_value(other.types[name], other.types, other.structs)
    end
  end
  return "*new(" .. t .. ")"
end

--- Treesitter node under the cursor of the current buffer (`row` 1-based, `col` 0-based; the character before the cursor)
---@param row integer
---@param col integer
---@return TSNode?
local function node_at(row, col)
  local ok, node = pcall(function()
    vim.treesitter.get_parser(0, "go"):parse()
    return vim.treesitter.get_node { pos = { row - 1, math.max(col - 1, 0) } }
  end)
  return ok and node or nil
end

--- Struct (with its fields) from how it is written (`ListFilter` | `domain.ListFilter`); one from another package is read from disk
---@param written string
---@param pkg GoImplPackage
---@param file_path string
---@return { fields: { name: string, type: string }[], alias: string? }?
local function resolve_struct(written, pkg, file_path)
  local alias, name = written:match "^([%w_]+)%.([%w_]+)$"
  if not alias then
    return pkg.structs[written] and { fields = pkg.structs[written] } or nil
  end
  local dir = dir_for(alias, pkg, file_path)
  if not dir or dir == pkg.dir then
    return nil
  end
  local other = package_at(dir)
  return other.structs[name] and { fields = other.structs[name], alias = alias } or nil
end

M.resolve_struct = resolve_struct
M.node_at = node_at
--- Idiomatic receiver name for a type: the initial of its LAST word (noteService → s, NoteHandler → h)
---@param name string
---@return string
local function receiver_name(name)
  local last = name:match "([%u][%l%d]*)$" or name
  local r = last:sub(1, 1):lower()
  return KEYWORDS[r] and r .. "_" or r
end

M.receiver_name = receiver_name
M.zero_for = zero_for
M.BUILTIN, M.KEYWORDS = BUILTIN, KEYWORDS
M.text, M.flat_params, M.scan, M.file_info = text, flat_params, scan, file_info
M.package_at, M.module_dir, M.module_packages = package_at, module_dir, module_packages
M.related, M.lower_first, M.resolve_interface, M.defined_methods =
  related, lower_first, resolve_interface, defined_methods
M.normalize, M.zero_value, M.esc, M.range_of = normalize, zero_value, esc, range_of
--- The names of the structs declared in the current file, in `type X struct` and in `type ( … )` blocks alike. Generic ones are left
--- out: their constructor would need the type parameters
---@return string[]
local function file_structs()
  local ok, root = pcall(function()
    return vim.treesitter.get_parser(0, "go"):parse()[1]:root()
  end)
  local names = {}
  if not ok or not root then
    return names
  end
  for decl in root:iter_children() do
    if decl:type() == "type_declaration" then
      for spec in decl:iter_children() do
        local name, typ = spec:field("name")[1], spec:field("type")[1]
        if
          spec:type() == "type_spec"
          and name
          and typ
          and typ:type() == "struct_type"
          and not spec:field("type_parameters")[1]
        then
          names[#names + 1] = vim.treesitter.get_node_text(name, 0)
        end
      end
    end
  end
  table.sort(names)
  return names
end

M.buffer_state, M.current_package, M.file_structs = buffer_state, current_package, file_structs

return M
