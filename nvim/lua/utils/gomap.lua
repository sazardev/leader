-- ── Go: mapeadores entre structs de capas distintas (sin LLM, 0 tokens) ──────
-- En arquitectura por capas se escribe una y otra vez `NoteResponse{ID: n.ID, Title: n.Title...}`. Para cada struct del
-- archivo cuyo nombre acaba en Response / Request / DTO / Model / Entity / Record / Input / Output..., busca su par en el módulo
-- (`NoteResponse` → `Note`, también `CreateNoteRequest` → `Note`) y, al empezar una declaración (`func `), ofrece:
--   func toNoteResponse(n *domain.Note) NoteResponse            del dominio al DTO
--   func toNoteResponses(ns []*domain.Note) []NoteResponse      la versión de lista
--   func (r NoteResponse) toNote() *domain.Note                 y de vuelta
-- Los campos se emparejan por nombre (sin distinguir mayúsculas ni `_`); si el origen tiene el campo privado y un getter
-- (`ID()`), usa el getter. Tipos distintos: conversión `domain.Status(x)` si es un tipo definido sobre un básico; si no, el
-- campo sale con un `// TODO` que dice qué no encaja. Los campos sin origen salen como TODO, no inventados.
local ix = require "utils.goindex"

local M = {}

local KIND = vim.lsp.protocol.CompletionItemKind
local FORMAT = vim.lsp.protocol.InsertTextFormat

local SUFFIXES = {
  "Response",
  "Request",
  "Payload",
  "Entity",
  "Record",
  "Output",
  "Input",
  "Model",
  "View",
  "DTO",
  "Dto",
  "Resp",
  "Req",
  "Row",
}
local PREFIXES = { "Create", "Update", "Patch", "Delete", "New", "List", "Get" }

--- Posibles nombres del struct "de dominio" de un DTO/modelo, del más probable al menos
---@param name string
---@return string[] bases, string? suffix
function M.bases(name)
  for _, suffix in ipairs(SUFFIXES) do
    if #name > #suffix and name:sub(-#suffix) == suffix then
      local base = name:sub(1, #name - #suffix)
      local out = {}
      for _, prefix in ipairs(PREFIXES) do
        if base:sub(1, #prefix) == prefix and #base > #prefix and base:sub(#prefix + 1, #prefix + 1):match "%u" then
          out[#out + 1] = base:sub(#prefix + 1)
        end
      end
      out[#out + 1] = base
      return out, suffix
    end
  end
  return {}, nil
end

---@param name string
---@return string
local function key(name)
  return (name:lower():gsub("_", ""))
end

local BASIC = ix.BUILTIN

---@param t string
---@return string
local function strip(t)
  return (t:gsub("[%w_]+%.", ""):gsub("^%*", ""))
end

--- Expresión para asignar `src` (de tipo `from`) a un campo de tipo `to`; y un comentario TODO si no encaja
---@param expr string
---@param from string
---@param to string
---@param qualify fun(t: string): string  califica un tipo del paquete destino (si es de otro paquete)
---@return string, string?
local function convert(expr, from, to, qualify)
  if from == to then
    return expr
  end
  local f, t = strip(from), strip(to)
  local from_ptr, to_ptr = from:sub(1, 1) == "*", to:sub(1, 1) == "*"
  if from_ptr ~= to_ptr then
    return expr, ("TODO: %s → %s (pointer vs value)"):format(from, to)
  end
  if f == t then
    return expr -- mismo tipo con otro calificador (domain.Note / Note)
  end
  if
    not to_ptr and ((BASIC[f] and not BASIC[t] and t:match "^%u") or (BASIC[t] and not BASIC[f] and f:match "^%u"))
  then
    return ("%s(%s)"):format(qualify(to), expr)
  end
  if f == "Time" or t == "Time" then
    return expr, ("TODO: %s → %s"):format(from, to)
  end
  return expr, ("TODO: %s → %s"):format(from, to)
end

---@class GoMapSide
---@field name string       nombre del struct
---@field written string    como se escribe en el archivo (`domain.Note` | `NoteResponse`)
---@field fields { name: string, type: string }[]
---@field methods table<string, GoImplMethod>  métodos sin parámetros y con un retorno (getters), por clave
---@field qualifier string? alias del paquete si es de otro paquete
---@field declared table<string, boolean> tipos declarados en su paquete

---@param pkg GoImplPackage
---@param name string
---@param written string
---@param qualifier string?
---@return GoMapSide
local function side(pkg, name, written, qualifier)
  local getters = {}
  for _, m in ipairs(pkg.methods) do
    if m.recv == name and m.params and #m.params == 0 and #m.results == 1 and m.name:match "^%u" then
      getters[key(m.name)] = m
    end
  end
  local declared = {}
  for n in pairs(pkg.structs) do
    declared[n] = true
  end
  for n in pairs(pkg.types) do
    declared[n] = true
  end
  for n in pairs(pkg.interfaces) do
    declared[n] = true
  end
  return {
    name = name,
    written = written,
    fields = pkg.structs[name] or {},
    methods = getters,
    qualifier = qualifier,
    declared = declared,
  }
end

---@param s GoMapSide
---@return fun(t: string): string
local function qualifier_of(s)
  return function(t)
    if s.qualifier and s.declared[t] then
      return s.qualifier .. "." .. t
    end
    return t
  end
end

--- Cuerpo `Field: expr,` de un literal que rellena `dst` desde `src` (`var` es la variable de origen)
---@param src GoMapSide
---@param dst GoMapSide
---@param var string
---@return string[]
local function assignments(src, dst, var)
  local by_key = {}
  for _, f in ipairs(src.fields) do
    by_key[key(f.name)] = f
  end
  local qualify = qualifier_of(dst)
  local lines = {}
  for _, f in ipairs(dst.fields) do
    if f.name:match "^%u" then
      local k = key(f.name)
      local source = by_key[k]
      local expr, from
      if source and source.name:match "^%u" then
        expr, from = ("%s.%s"):format(var, source.name), source.type
      elseif src.methods[k] then
        local m = src.methods[k]
        expr, from = ("%s.%s()"):format(var, m.name), m.results[1]
      elseif source then
        expr, from = nil, nil
        lines[#lines + 1] = ("\t\t// TODO: %s (%s): source field %s is unexported and has no getter"):format(
          f.name,
          f.type,
          source.name
        )
      end
      if expr then
        local value, todo = convert(expr, from, f.type, qualify)
        lines[#lines + 1] = ("\t\t%s: %s,%s"):format(f.name, value, todo and (" // " .. todo) or "")
      elseif not source then
        lines[#lines + 1] = ("\t\t// TODO: %s (%s) has no source field in %s"):format(f.name, f.type, src.name)
      end
    end
  end
  return lines
end

---@param name string
---@return string
local function var_of(name)
  return ix.lower_first(name)
end

---@param dst GoMapSide
---@return boolean
local function has_private_fields(dst)
  for _, f in ipairs(dst.fields) do
    if not f.name:match "^%u" then
      return true
    end
  end
  return false
end

---@class GoMapPair
---@field a GoMapSide  el struct del archivo (DTO/modelo)
---@field p GoMapSide  su par (dominio)
---@field suffix string

--- Pares (struct del archivo, struct de dominio) del archivo actual
---@param pkg GoImplPackage
---@param path string
---@param src string
---@return GoMapPair[]
local function pairs_in_buffer(pkg, path, src)
  local out = {}
  local module = ix.module_packages(path)
  local names = vim.tbl_keys(pkg.structs)
  table.sort(names)
  for _, name in ipairs(names) do
    local bases, suffix = M.bases(name)
    if suffix and src:find("type%s+" .. name .. "%s+struct") then
      local found
      for _, base in ipairs(bases) do
        if pkg.structs[base] and base ~= name then
          found = { side(pkg, base, base, nil) }
        else
          -- primero lo importado por el archivo; luego cualquier paquete del módulo
          local imported = {}
          for alias, import_path in pairs(pkg.imports) do
            imported[import_path] = alias
          end
          local best
          for _, other in ipairs(module and module.packages or {}) do
            if other.dir ~= pkg.dir and other.structs[base] and (not best or imported[other.import_path]) then
              best = other
            end
          end
          if best then
            local alias = imported[best.import_path] or best.name or vim.fs.basename(best.dir)
            found = { side(best, base, alias .. "." .. base, alias) }
          end
        end
        if found then
          break
        end
      end
      if found then
        out[#out + 1] = { a = side(pkg, name, name, nil), p = found[1], suffix = suffix }
      end
    end
  end
  return out
end

---@param range table
---@param frag string
---@return table[]
function M.declaration_items(range, frag)
  local pkg, path = ix.current_package()
  if not pkg then
    return {}
  end
  local _, src = ix.buffer_state()
  local model_file = require("utils.gomodel").is_model_file()
  local have = {}
  for _, f in ipairs(pkg.funcs) do
    have[f.name] = true
  end
  for _, m in ipairs(pkg.methods) do
    have[m.recv .. "." .. m.name] = true
  end

  local items = {}
  local function add(label, detail, text, filter)
    items[#items + 1] = {
      label = label,
      labelDetails = { description = detail },
      kind = KIND.Snippet,
      insertTextFormat = FORMAT.PlainText,
      filterText = filter,
      sortText = ("%03d"):format(#items + 1),
      documentation = { kind = "markdown", value = "```go\n" .. text .. "\n```" },
      textEdit = { newText = text, range = range },
    }
  end

  for _, pair in ipairs(pairs_in_buffer(pkg, path, src)) do
    local a, p = pair.a, pair.p
    -- gomodel ya ofrece toDomain/fromDomain en los archivos de modelo
    if not (model_file and pair.suffix == "Model") then
      local pbase = p.name
      local pvar, avar = var_of(pbase), ix.receiver_name(a.name) -- NoteResponse → r (el param del dominio: n)
      if avar == pvar then
        avar = "x"
      end
      local to_a = "to" .. a.name
      local detail = ("%s → %s"):format(p.written, a.name)
      if not have[to_a] then
        local body = assignments(p, a, pvar)
        add(
          "func " .. to_a,
          detail,
          ("func %s(%s *%s) %s {\n\treturn %s{\n%s\n\t}\n}"):format(
            to_a,
            pvar,
            p.written,
            a.name,
            a.name,
            table.concat(body, "\n")
          ),
          ("func %s map to %s %s"):format(to_a, a.name, p.name)
        )
      end
      local to_as = to_a .. "s"
      if not have[to_as] then
        add(
          "func " .. to_as,
          detail .. " (list)",
          ("func %s(%ss []*%s) []%s {\n\tout := make([]%s, 0, len(%ss))\n\tfor _, %s := range %ss {\n\t\tout = append(out, %s(%s))\n\t}\n\treturn out\n}"):format(
            to_as,
            pvar,
            p.written,
            a.name,
            a.name,
            pvar,
            pvar,
            pvar,
            to_a,
            pvar
          ),
          ("func %s map list to %s %s"):format(to_as, a.name, p.name)
        )
      end
      local back = "to" .. p.name
      if not have[a.name .. "." .. back] then
        local body = assignments(a, p, avar)
        local note = has_private_fields(p)
            and ("\n\t\t// TODO: %s has unexported fields: build it with its constructor instead"):format(p.written)
          or ""
        add(
          ("func (%s %s) %s"):format(avar, a.name, back),
          ("%s → %s"):format(a.name, p.written),
          ("func (%s %s) %s() *%s {\n\treturn &%s{\n%s%s\n\t}\n}"):format(
            avar,
            a.name,
            back,
            p.written,
            p.written,
            table.concat(body, "\n"),
            note
          ),
          ("func method %s %s map to %s"):format(a.name, back, p.name)
        )
      end
    end
  end
  return vim.tbl_filter(function(it)
    return frag == "" or ("func"):find(frag:lower(), 1, true) == 1 or it.filterText:lower():find(frag:lower(), 1, true)
  end, items)
end

return M
