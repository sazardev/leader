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

local ix = require "utils.goindex"
local KEYWORDS = ix.KEYWORDS
local BUILTIN = ix.BUILTIN
local package_at, module_dir = ix.package_at, ix.module_dir
local related, lower_first, resolve_interface, defined_methods =
  ix.related, ix.lower_first, ix.resolve_interface, ix.defined_methods
local normalize, zero_value, esc, range_of = ix.normalize, ix.zero_value, ix.esc, ix.range_of
local buffer_state, current_package = ix.buffer_state, ix.current_package

-- ── qué interfaz implementa un struct y qué le falta ─────────────────────────

---@class GoImplTarget
---@field struct string
---@field iface string          nombre como se escribe (`NoteService`, `domain.NoteRepository`)
---@field methods GoImplMethod[] los que FALTAN
---@field alias string?         paquete de la interfaz si es de otro paquete
---@field declared table<string, boolean>? tipos declarados en el paquete de la interfaz (se califican con `alias`)
---@field recv string           nombre del receptor
---@field ptr boolean

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
          recv = first and first.var or ix.receiver_name(struct),
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

--- Interfaces que se le atribuyen a un struct (para `var _ I = (*T)(nil)`), en orden de confianza
---@param pkg GoImplPackage
---@param struct string
---@param file_path string
---@return string[]
function M.candidates(pkg, struct, file_path)
  return candidates(pkg, struct, file_path)
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
