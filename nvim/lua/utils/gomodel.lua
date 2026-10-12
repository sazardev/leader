-- ── Atajos para archivos de modelo de Go (`*_model.go` / `model.go`) ─────────
-- Solo existen en esos archivos, para que no salgan en cada struct de cada paquete.
-- Los consume `utils/gosmart.lua` al empezar una declaración (columna 0):
--   functable        → func (NoteModel) TableName() string { return "notes" }       (gorm)
--   funcdomain       → toDomain + fromDomain de una vez
--   functodomain     → func (m NoteModel) toDomain() *note.Note { return note.Reconstitute(m.ID, …) }
--   funcfromdomain   → func fromDomain(n *note.Note) NoteModel { return NoteModel{ID: n.ID(), …} }
-- El dominio sale del nombre: `NoteModel` → `note.Note`. Si el archivo importa `…/note` y el
-- paquete está en el módulo, se lee su constructor real (Reconstitute, Rehydrate, Restore…).
local M = {}

local KIND = vim.lsp.protocol.CompletionItemKind
local FORMAT = vim.lsp.protocol.InsertTextFormat

-- letras tecleadas para que salga un atajo `func…` (igual que `funcnew`)
M.MIN = 5

-- Constructores de rehidratación que se buscan en el paquete de dominio, por orden
local CONSTRUCTORS = { "Reconstitute", "Rehydrate", "Restore", "Hydrate", "FromPersistence", "Load" }

---@return boolean
function M.is_model_file()
  local name = vim.fs.basename(vim.api.nvim_buf_get_name(0))
  return name == "model.go" or name:match "_model%.go$" ~= nil
end

---@param word string
---@param frag string
local function starts(word, frag)
  return frag == "" or word:lower():sub(1, #frag) == frag:lower()
end

--- `NoteModel` → `notes` (sin sufijo Model, snake_case, plural simple en inglés)
---@param struct string
---@return string
local function table_name(struct)
  local base = struct:gsub("Model$", "")
  local snake = require("utils.gotags").snake(base ~= "" and base or struct)
  if snake:match "[^aeiou]y$" then
    return snake:sub(1, -2) .. "ies"
  elseif snake:match "[sxz]$" or snake:match "[cs]h$" then
    return snake .. "es"
  end
  return snake .. "s"
end

---@class GoDomain
---@field pkg string alias del paquete (`note`)
---@field ctor? string constructor de rehidratación encontrado en el paquete

--- Paquete de dominio de `base` (`Note` → `note`) y su constructor, si se puede leer
---@param base string
---@param buf string texto del archivo
---@return GoDomain
local function domain_info(base, buf)
  local pkg = base:lower():gsub("[^%w]", "")
  local info = { pkg = pkg }

  local import = buf:match('"([^"\n]*/' .. pkg .. ')"')
  local gomod = vim.fs.find("go.mod", { path = vim.fs.dirname(vim.api.nvim_buf_get_name(0)), upward = true })[1]
  if not import or not gomod then
    return info
  end

  local module
  for _, line in ipairs(vim.fn.readfile(gomod, "", 5)) do
    module = module or line:match "^module%s+(%S+)"
  end
  if not module or import:sub(1, #module + 1) ~= module .. "/" then
    return info
  end

  local dir = vim.fs.dirname(gomod) .. "/" .. import:sub(#module + 2)
  local source = {}
  for _, file in ipairs(vim.fn.glob(dir .. "/*.go", false, true)) do
    if not file:match "_test%.go$" then
      source[#source + 1] = table.concat(vim.fn.readfile(file), "\n")
    end
  end
  local text = table.concat(source, "\n")
  for _, ctor in ipairs(CONSTRUCTORS) do
    if text:find("func%s+" .. ctor .. "%s*%(") then
      info.ctor = ctor
      break
    end
  end
  return info
end

---@param s GoStruct
---@param base string
---@param d GoDomain
---@return string
local function to_domain_text(s, base, d)
  local args = {}
  for _, f in ipairs(s.fields) do
    args[#args + 1] = "m." .. f.name
  end
  return ("func (m %s) toDomain() *%s.%s {\n\treturn %s.%s(%s)\n}"):format(
    s.name,
    d.pkg,
    base,
    d.pkg,
    d.ctor or "${1:Reconstitute}",
    table.concat(args, ", ")
  )
end

---@param s GoStruct
---@param base string
---@param d GoDomain
---@param fname string
---@return string
local function from_domain_text(s, base, d, fname)
  local param = base:sub(1, 1):lower()
  local lines = {}
  for _, f in ipairs(s.fields) do
    lines[#lines + 1] = ("\t\t%s: %s.%s(),"):format(f.name, param, f.name)
  end
  return ("func %s(%s *%s.%s) %s {\n\treturn %s{\n%s\n\t}\n}"):format(
    fname,
    param,
    d.pkg,
    base,
    s.name,
    s.name,
    table.concat(lines, "\n")
  )
end

---@class GoModelOpts
---@field structs GoStruct[] structs del archivo
---@field buf string texto del archivo
---@field mode "func"|"type"|"any"
---@field frag string lo ya tecleado
---@field want_funcs boolean se está empezando un `func`
---@field range table

--- Atajos a poner AL PRINCIPIO de la lista (para no bajar hasta la última opción)
---@param o GoModelOpts
---@return table[]
function M.items(o)
  if o.mode == "type" or not M.is_model_file() then
    return {}
  end
  local mode, frag, buf = o.mode, o.frag, o.buf

  -- `func ` lista lo esencial; los atajos sueltos salen al teclearlos (`short` ≥ 2 letras o `full` ≥ MIN)
  local function typed(full, short)
    return mode == "any" and ((short and #frag >= 2 and starts(short, frag)) or (#frag >= M.MIN and starts(full, frag)))
  end
  local want = {
    table = o.want_funcs or typed("functable", "TableName"),
    both = o.want_funcs or typed("funcdomain"),
    to = typed("functodomain", "toDomain"),
    from = typed("funcfromdomain", "fromDomain"),
  }

  local models = {}
  for _, s in ipairs(o.structs) do
    local base = s.name:match "^(.+)Model$"
    if base and #s.fields > 0 then
      models[#models + 1] = { s = s, base = base }
    end
  end
  local single_model = #models == 1

  local items = {}
  ---@param label string
  ---@param detail string
  ---@param text string
  ---@param filter string
  local function add(label, detail, text, filter)
    items[#items + 1] = {
      label = label,
      labelDetails = { description = detail },
      kind = KIND.Snippet,
      insertTextFormat = FORMAT.Snippet,
      filterText = label .. " " .. filter,
      sortText = ("%03d"):format(#items),
      textEdit = { newText = text, range = o.range },
    }
  end

  -- gorm: TableName() para los structs que aún no lo tienen
  if want.table then
    local pending = {}
    for _, s in ipairs(o.structs) do
      if not buf:find("%(%s*%w*%s*%*?" .. s.name .. "%s*%)%s*TableName%s*%(") then
        pending[#pending + 1] = s
      end
    end
    for _, s in ipairs(pending) do
      local name = table_name(s.name)
      add(
        #pending == 1 and "functable" or "functable " .. s.name,
        ("→ TableName() %q"):format(name),
        ("func (%s) TableName() string {\n\treturn \"${1:%s}\"\n}"):format(s.name, name),
        "TableName func method"
      )
    end
  end

  -- mapeadores modelo ↔ dominio
  for _, m in ipairs(models) do
    local d = domain_info(m.base, buf)
    local fname = single_model and "fromDomain" or ("from%sDomain"):format(m.base)
    local has_to = buf:find("%(%s*%w*%s*%*?" .. m.s.name .. "%s*%)%s*toDomain%s*%(") ~= nil
    local has_from = buf:find("func%s+" .. fname .. "%s*%(") ~= nil
    local suffix = single_model and "" or " " .. m.base
    local what = ("%s.%s"):format(d.pkg, m.base)

    if want.both and not has_to and not has_from then
      add(
        "funcdomain" .. suffix,
        "→ toDomain + " .. fname,
        to_domain_text(m.s, m.base, d) .. "\n\n" .. from_domain_text(m.s, m.base, d, fname),
        "toDomain fromDomain mapper func"
      )
    end
    if want.to and not has_to then
      add("functodomain" .. suffix, "→ " .. what, to_domain_text(m.s, m.base, d), "toDomain mapper func method")
    end
    if want.from and not has_from then
      add("funcfromdomain" .. suffix, "← " .. what, from_domain_text(m.s, m.base, d, fname), fname .. " mapper func")
    end
  end
  return items
end

return M
