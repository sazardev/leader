-- ── Go: lo que falta por implementar de una interfaz (sin LLM, 0 tokens) ─────
-- Si un struct ya "se nota" implementando una interfaz y le faltan métodos, ofrece EXACTAMENTE esos, con la firma de
-- la interfaz y un cuerpo útil, como completado de blink (lo consume utils/gosmart.lua):
--   func (s *noteService) |        → los métodos que faltan (tras escribir el receptor), y "todos los que faltan"
--   func |  (columna 0)            → lo mismo para cada struct del archivo, con el receptor ya escrito
-- Cómo sabe qué interfaz implementa un struct (la primera que encaje, por este orden):
--   1. `var _ NoteService = (*noteService)(nil)`            (la comprobación idiomática)
--   2. un constructor que la devuelve: `func NewX(...) NoteService { return &noteService{...} }`
--   3. el nombre: noteService ~ NoteService, postgresNoteRepository ~ domain.NoteRepository (paquetes locales importados)
--   4. lo que ya implementó: si sus métodos son un subconjunto de los de la interfaz
-- Cuerpo: si el struct guarda una dependencia que es una interfaz (`repo domain.NoteRepository`) y esta tiene un método
-- con la MISMA forma (tipos de parámetros y de retorno, sin importar el paquete), el cuerpo la llama:
-- `return s.repo.FindByID(ctx, id)`. Si no, deja el cursor en el cuerpo con `return` de valores cero que compila.
-- Las interfaces de OTRO paquete del módulo (`domain.NoteRepository`) se leen del disco (módulo de go.mod) y sus tipos
-- se califican (`Note` → `domain.Note`); los imports que falten los pone goimports al guardar.
-- Interfaces de la librería estándar o de dependencias no se leen: para esas, gopls ("Declare missing methods", <leader>ca).
local M = {}

local KIND = vim.lsp.protocol.CompletionItemKind
local FORMAT = vim.lsp.protocol.InsertTextFormat

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

-- ── lectura de un archivo (treesitter sobre texto) ───────────────────────────

---@class GoImplMethod
---@field name string
---@field sig string        `(ctx context.Context, id string) (*Note, error)` tal como está en la interfaz
---@field refs { pos: integer, name: string }[] tipos sin calificar dentro de `sig` (se califican al usar la interfaz desde otro paquete)
---@field params { name: string?, type: string }[]
---@field results string[]
---@field named boolean     todos los parámetros tienen nombre

---@class GoImplFile
---@field pkg string?
---@field imports table<string, string> alias → ruta de import
---@field interfaces table<string, GoImplMethod[]>
---@field structs table<string, { name: string, type: string }[]>
---@field types table<string, string> tipos definidos que no son struct ni interfaz (`Kind` → `string`)
---@field methods { recv: string, name: string, ptr: boolean, var: string? }[]
---@field ctors { result: string, builds: table<string, boolean> }[]
---@field asserts { iface: string, typ: string }[]

---@param n TSNode
---@param src string
local function text(n, src)
  return vim.treesitter.get_node_text(n, src)
end

--- Tipos locales sin calificar dentro de `n` (posición en bytes relativa al inicio de `n`)
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

--- parameter_list → lista plana { name?, type } (un elemento por nombre) y si todos tienen nombre
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

---@param spec_type TSNode interface_type
---@param src string
---@return GoImplMethod[]
local function interface_methods(spec_type, src)
  local methods = {}
  for elem in spec_type:iter_children() do
    if elem:type() == "method_elem" then
      local name, params, result = elem:field("name")[1], elem:field("parameters")[1], elem:field("result")[1]
      if name and params then
        local last = result or params
        local _, _, first_byte = params:range(true)
        local _, _, _, _, _, last_byte = last:range(true)
        local sig = src:sub(first_byte + 1, last_byte)
        local _, _, elem_byte = elem:range(true)
        local refs = {}
        for _, r in ipairs(local_type_refs(elem, src)) do
          local pos = r.pos + elem_byte - first_byte -- posición dentro de `sig` (los nombres de parámetros no cuentan)
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
        methods[#methods + 1] = {
          name = text(name, src),
          sig = sig,
          refs = refs,
          params = plist,
          results = results,
          named = named,
        }
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
  local info = { imports = {}, interfaces = {}, structs = {}, types = {}, methods = {}, ctors = {}, asserts = {} }

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
        info.methods[#info.methods + 1] =
          { recv = text(base, src), name = text(name, src), ptr = ptr, var = var and text(var, src) or nil }
      end
    elseif t == "function_declaration" then
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

-- ── índice de un paquete (archivos del directorio, en caché por fecha) ───────

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
---@field imports table<string, string>

--- Paquete de un directorio. `live` = { path, text } sustituye a su archivo en disco (el buffer sin guardar)
---@param dir string
---@param live { path: string, text: string }?
---@return GoImplPackage
local function package_at(dir, live)
  ---@type GoImplPackage
  local pkg =
    { dir = dir, interfaces = {}, structs = {}, types = {}, methods = {}, ctors = {}, asserts = {}, imports = {} }
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

--- Directorio de un import que pertenece al módulo (`notesapi/internal/domain` → <raíz>/internal/domain)
---@param import_path string
---@param from string archivo desde el que se importa
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

-- ── qué interfaz implementa un struct y qué le falta ─────────────────────────

---@class GoImplTarget
---@field struct string
---@field iface string          nombre como se escribe (`NoteService`, `domain.NoteRepository`)
---@field methods GoImplMethod[] los que FALTAN
---@field alias string?         paquete de la interfaz si es de otro paquete
---@field declared table<string, boolean>? tipos declarados en el paquete de la interfaz (se califican con `alias`)
---@field recv string           nombre del receptor
---@field ptr boolean

---@param a string
---@param b string
---@return boolean
local function related(a, b)
  a, b = a:lower(), b:lower()
  if a == b then
    return true
  end
  -- uno contiene al otro (noteService ~ NoteService, postgresNoteRepository ~ NoteRepository); el corto, de 4+ letras
  local short, long = #a < #b and a or b, #a < #b and b or a
  return #short >= 4 and long:find(short, 1, true) ~= nil
end

---@param name string
---@return string
local function lower_first(name)
  local r = name:sub(1, 1):lower()
  return KEYWORDS[r] and r .. "_" or r
end

--- Interfaz (con sus métodos) a partir de como se escribe; la de otro paquete se lee de disco
---@param written string `NoteService` | `domain.NoteRepository`
---@param pkg GoImplPackage
---@param file_path string
---@return GoImplMethod[]?, string? alias, table<string, boolean>? declared
local function resolve_interface(written, pkg, file_path)
  local alias, name = written:match "^([%w_]+)%.([%w_]+)$"
  if not alias then
    return pkg.interfaces[written]
  end
  local import_path = pkg.imports[alias]
  local dir = import_path and module_dir(import_path, file_path)
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

--- Interfaces candidatas del struct, en orden de confianza (sin repetir)
---@param pkg GoImplPackage
---@param struct string
---@param file_path string
---@return string[]
local function candidates(pkg, struct, file_path)
  local found, seen = {}, {}
  local function add(written)
    if written and not seen[written] then
      seen[written] = true
      found[#found + 1] = written
    end
  end
  for _, a in ipairs(pkg.asserts) do
    if a.typ == struct then
      add(a.iface)
    end
  end
  for _, c in ipairs(pkg.ctors) do
    if c.builds[struct] then
      add(c.result)
    end
  end
  for iface in pairs(pkg.interfaces) do
    if related(iface, struct) then
      add(iface)
    end
  end
  -- paquetes locales importados: `postgresNoteRepository` ~ domain.NoteRepository
  for alias, import_path in pairs(pkg.imports) do
    local dir = module_dir(import_path, file_path)
    if dir and dir ~= pkg.dir then
      for iface in pairs(package_at(dir).interfaces) do
        if related(iface, struct) then
          add(alias .. "." .. iface)
        end
      end
    end
  end
  -- lo que ya implementó: sus métodos son un subconjunto de los de la interfaz
  local mine = defined_methods(pkg, struct)
  if next(mine) then
    for iface, methods in pairs(pkg.interfaces) do
      local names = {}
      for _, m in ipairs(methods) do
        names[m.name] = true
      end
      local total, hit = 0, 0
      for name in pairs(mine) do
        if name:match "^%u" then
          total = total + 1
          hit = hit + (names[name] and 1 or 0)
        end
      end
      if total > 0 and hit == total then
        add(iface)
      end
    end
  end
  return found
end

---@param pkg GoImplPackage
---@param struct string
---@param file_path string
---@return GoImplTarget[]
local function missing_for(pkg, struct, file_path)
  local mine = defined_methods(pkg, struct)
  local first = vim.tbl_filter(function(m)
    return m.recv == struct
  end, pkg.methods)[1]
  local out = {}
  for _, written in ipairs(candidates(pkg, struct, file_path)) do
    local methods, alias, declared = resolve_interface(written, pkg, file_path)
    if methods then
      local missing = vim.tbl_filter(function(m)
        return not mine[m.name]
      end, methods)
      if #missing > 0 then
        out[#out + 1] = {
          struct = struct,
          iface = written,
          methods = missing,
          alias = alias,
          declared = declared,
          recv = first and first.var or lower_first(struct),
          ptr = first == nil or first.ptr,
        }
      end
    end
  end
  return out
end

-- ── cuerpo y firma ───────────────────────────────────────────────────────────

--- Firma con los tipos de la interfaz calificados si viene de otro paquete
---@param m GoImplMethod
---@param target GoImplTarget
---@return string
local function signature(m, target)
  local sig = m.sig
  if target.alias and target.declared then
    local out, last = {}, 0
    for _, r in ipairs(m.refs) do
      if target.declared[r.name] then
        out[#out + 1] = sig:sub(last + 1, r.pos) .. target.alias .. "."
        last = r.pos
      end
    end
    out[#out + 1] = sig:sub(last + 1)
    sig = table.concat(out)
  end
  return sig
end

--- Nombre corto de un parámetro a partir de su tipo (`context.Context` → ctx, `*domain.Note` → note, `UserID` → userID)
---@param t string
---@return string?
local function name_from_type(t)
  if t:match "context%.Context$" then
    return "ctx"
  end
  local base = t:gsub("^[%*%[%]%.]+", ""):match "([%a_][%w_]*)$"
  if not base or BUILTIN[base] then
    return nil
  end
  return (
    base
      :gsub("^(%u+)(%u%l)", function(a, b)
        return a:lower() .. b
      end)
      :gsub("^%u", string.lower)
  )
end

--- Nombres de los parámetros (los de la interfaz, o inventados y sin repetir cuando no los tiene)
---@param m GoImplMethod
---@return string[]
local function param_names(m)
  local used, names = {}, {}
  for i, p in ipairs(m.params) do
    local name = p.name or name_from_type(p.type) or ("arg" .. i)
    local unique, n = name, 1
    while used[unique] or KEYWORDS[unique] do
      n = n + 1
      unique = name .. n
    end
    used[unique] = true
    names[i] = unique
  end
  return names
end

--- Firma con nombres en todos los parámetros (la de la interfaz si ya los tiene)
---@param m GoImplMethod
---@param target GoImplTarget
---@param names string[]
---@return string
local function named_signature(m, target, names)
  local sig = signature(m, target)
  if m.named then
    return sig
  end
  local ret = sig:match "^%b()%s*(.*)$" or ""
  local parts = {}
  for i, p in ipairs(m.params) do
    parts[i] = names[i] .. " " .. p.type
  end
  return "(" .. table.concat(parts, ", ") .. ")" .. (ret ~= "" and (" " .. ret) or "")
end

---@param t string
---@return string
local function normalize(t)
  return (t:gsub("[%w_]+%.", ""))
end

---@param m GoImplMethod
---@return string
local function shape(m)
  local ps = {}
  for _, p in ipairs(m.params) do
    ps[#ps + 1] = normalize(p.type)
  end
  local rs = {}
  for _, r in ipairs(m.results) do
    rs[#rs + 1] = normalize(r)
  end
  return table.concat(ps, ",") .. "->" .. table.concat(rs, ",")
end

---@param pkg GoImplPackage
---@param struct string
---@param file_path string
---@return { field: string, methods: GoImplMethod[] }[]
local function dependencies(pkg, struct, file_path)
  local deps = {}
  for _, f in ipairs(pkg.structs[struct] or {}) do
    local methods = resolve_interface(f.type, pkg, file_path)
    if methods then
      deps[#deps + 1] = { field = f.name, methods = methods }
    end
  end
  return deps
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

--- Un método completo: `Name(params) results {\n\tbody\n}` (con la cabecera `func (r *T) ` si `header`)
---@param m GoImplMethod
---@param target GoImplTarget
---@param pkg GoImplPackage
---@param deps { field: string, methods: GoImplMethod[] }[]
---@param header boolean
---@param stop string  marcador de snippet donde queda el cursor: `$0` (uno solo) o `$N` (varios métodos de una vez)
---@return string snippet, string plain
local function render(m, target, pkg, deps, header, stop)
  local names = param_names(m)
  local sig = named_signature(m, target, names)
  local recv = ("(%s %s%s)"):format(target.recv, target.ptr and "*" or "", target.struct)

  -- ¿alguna dependencia tiene un método con la misma forma? (mismo nombre gana si hay varios)
  local call
  local want = shape(m)
  for _, dep in ipairs(deps) do
    local best
    for _, d in ipairs(dep.methods) do
      if shape(d) == want and (not best or d.name == m.name) then
        best = d
      end
    end
    if best then
      local args = {}
      for i, p in ipairs(m.params) do
        args[i] = names[i] .. (p.type:sub(1, 3) == "..." and "..." or "")
      end
      call = ("%s.%s.%s(%s)"):format(target.recv, dep.field, best.name, table.concat(args, ", "))
      break
    end
  end

  local body_snippet, body_plain
  if call then
    local prefix = #m.results > 0 and "return " or ""
    -- una llamada ya hecha no necesita cursor; solo con un método el cursor acaba al final
    body_snippet = "\t" .. prefix .. esc(call) .. (stop == "$0" and "$0" or "")
    body_plain = "\t" .. prefix .. call
  else
    local zeros = {}
    for i, r in ipairs(m.results) do
      zeros[i] = zero_value(r, pkg.types, pkg.structs)
    end
    local ret = #zeros > 0 and ("\treturn " .. table.concat(zeros, ", ")) or nil
    body_snippet = "\t" .. stop .. (ret and ("\n" .. esc(ret)) or "")
    body_plain = ret or "\t"
  end
  local head = (header and ("func " .. recv .. " ") or "") .. m.name .. sig .. " {\n"
  local plain = head .. body_plain .. "\n}"
  return esc(head) .. body_snippet .. "\n}", plain
end

-- ── ítems de blink ───────────────────────────────────────────────────────────

---@param plain string
---@param iface string
---@return table
local function documentation(plain, iface)
  return { kind = "markdown", value = ("`%s` · missing\n```go\n%s\n```"):format(iface, plain) }
end

---@param row integer
---@param from integer columna donde empieza lo que se reemplaza
---@param col integer
local function range_of(row, from, col)
  return { start = { line = row - 1, character = from }, ["end"] = { line = row - 1, character = col } }
end

--- Ítems de los métodos que le faltan a `struct`
---@param target GoImplTarget[]
---@param pkg GoImplPackage
---@param file_path string
---@param range table
---@param header boolean  el texto lleva `func (r *T) ` (empezando una declaración) o solo el nombre
---@param order_from integer
---@return table[]
local function items_for(targets, pkg, file_path, range, header, order_from)
  local items = {}
  for _, tg in ipairs(targets) do
    local deps = dependencies(pkg, tg.struct, file_path)
    local recv = ("func (%s %s%s)"):format(tg.recv, tg.ptr and "*" or "", tg.struct)
    local snippets, plains = {}, {}
    for _, m in ipairs(tg.methods) do
      local snip, plain = render(m, tg, pkg, deps, header, "$0")
      snippets[#snippets + 1], plains[#plains + 1] = snip, plain
      items[#items + 1] = {
        label = header and (recv .. " " .. m.name) or m.name,
        labelDetails = { description = tg.iface .. " · missing" },
        kind = KIND.Method,
        insertTextFormat = FORMAT.Snippet,
        filterText = header and ("func method %s %s"):format(tg.struct, m.name) or m.name,
        sortText = ("%03d"):format(order_from + #items + 1),
        documentation = documentation(plain, tg.iface),
        textEdit = { newText = snip, range = range },
      }
    end
    if #tg.methods > 1 then
      -- todos de una vez: el primero ya va en la posición del cursor; los demás, con su cabecera completa
      local joined, joined_plain = {}, {}
      for i, m in ipairs(tg.methods) do
        -- varios métodos: un solo `$0` no puede repetirse, así que cada cuerpo vacío lleva su propio `$N` (Tab salta)
        local snip, plain = render(m, tg, pkg, deps, header or i > 1, "$" .. i)
        joined[i], joined_plain[i] = snip, plain
      end
      table.insert(items, #items - #tg.methods + 1, {
        label = header and (recv .. " …all missing (" .. #tg.methods .. ")")
          or ("…all missing (" .. #tg.methods .. ")"),
        labelDetails = { description = tg.iface },
        kind = KIND.Method,
        insertTextFormat = FORMAT.Snippet,
        filterText = header and ("func method %s all missing"):format(tg.struct) or "all missing",
        sortText = ("%03d"):format(order_from),
        documentation = documentation(table.concat(joined_plain, "\n\n"), tg.iface),
        textEdit = { newText = table.concat(joined, "\n\n"), range = range },
      })
    end
  end
  return items
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

--- Posición `func (s *noteService) Ge|`: el struct del receptor, lo tecleado del nombre y cómo se escribió el receptor
---@param line string
---@param col integer
---@return string? struct, string? frag, integer? from, { var: string, ptr: boolean }? receiver
function M.method_position(line, col)
  local before = line:sub(1, col)
  local var, star, struct, frag = before:match "^func%s*%(%s*([%w_]*)%s*(%*?)%s*([%a_][%w_]*)%s*%)%s+([%w_]*)$"
  if not struct then
    return nil
  end
  return struct, frag, col - #frag, { var = var, ptr = star == "*" }
end

--- Ítems al escribir el nombre de un método (tras `func (s *T) `)
---@param ctx { line: string, cursor: integer[] }
---@return table[]
function M.method_items(ctx)
  local struct, frag, from, receiver = M.method_position(ctx.line, ctx.cursor[2])
  if not struct then
    return {}
  end
  local pkg, path = current_package()
  if not pkg or not pkg.structs[struct] then
    return {}
  end
  local targets = missing_for(pkg, struct, path)
  for _, tg in ipairs(targets) do
    -- el receptor se escribe como lo tecleaste (`s *noteService`): los cuerpos usan ese nombre
    tg.recv, tg.ptr = receiver.var ~= "" and receiver.var or tg.recv, receiver.ptr
  end
  local items = items_for(targets, pkg, path, range_of(ctx.cursor[1], from, ctx.cursor[2]), false, 0)
  return vim.tbl_filter(function(it)
    return frag == "" or it.filterText:lower():sub(1, #frag) == frag:lower()
  end, items)
end

--- Ítems al EMPEZAR una declaración: para cada struct del archivo al que le faltan métodos
---@param range table
---@param frag string lo tecleado tras `func ` (o la palabra, en modo `any`)
---@return table[]
function M.declaration_items(range, frag)
  local pkg, path = current_package()
  if not pkg then
    return {}
  end
  local targets = {}
  local _, src = buffer_state()
  for struct in pairs(pkg.structs) do
    -- solo los structs de ESTE archivo: los del resto del paquete salen al escribir su receptor
    if src:find("type%s+" .. struct .. "%s+struct") then
      vim.list_extend(targets, missing_for(pkg, struct, path))
    end
  end
  table.sort(targets, function(a, b)
    return a.struct < b.struct
  end)
  local items = items_for(targets, pkg, path, range, true, 0)
  return vim.tbl_filter(function(it)
    return frag == "" or ("func"):find(frag:lower(), 1, true) == 1 or it.filterText:lower():find(frag:lower(), 1, true)
  end, items)
end

--- Para pruebas: lo que le falta a un struct, sin armar ítems
---@param struct string
---@return { iface: string, missing: string[] }[]
function M.missing(struct)
  local pkg, path = current_package()
  if not pkg then
    return {}
  end
  return vim.tbl_map(function(t)
    return {
      iface = t.iface,
      missing = vim.tbl_map(function(m)
        return m.name
      end, t.methods),
    }
  end, missing_for(pkg, struct, path))
end

return M
