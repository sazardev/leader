-- ── Shortcuts for Go model files (`*_model.go` / `model.go`) ──────────────────
-- They only exist in those files, so they don't show up for every struct of every package.
-- `utils/gosmart.lua` consumes them when starting a declaration (column 0):
--   functable        → func (NoteModel) TableName() string { return "notes" }       (gorm)
--   funcdomain       → toDomain + fromDomain at once
--   functodomain     → func (m NoteModel) toDomain() *note.Note { return note.Reconstitute(m.ID, …) }
--   funcfromdomain   → func fromDomain(n *note.Note) NoteModel { return NoteModel{ID: n.ID(), …} }
-- The domain comes from the name: `NoteModel` → `note.Note`. If the file imports `…/note` and the
-- package is in the module, its real constructor is read (Reconstitute, Rehydrate, Restore…).
local M = {}

local KIND = vim.lsp.protocol.CompletionItemKind
local FORMAT = vim.lsp.protocol.InsertTextFormat

-- typed letters needed for a `func…` shortcut to show up (same as `funcnew`)
M.MIN = 5

-- Rehydration constructors looked up in the domain package, in order
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

--- `NoteModel` → `notes` (no Model suffix, snake_case, simple English plural)
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
---@field pkg string package alias (`note`)
---@field ctor? string rehydration constructor found in the package

--- Domain package of `base` (`Note` → `note`) and its constructor, if it can be read
---@param base string
---@param buf string file text
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
---@field structs GoStruct[] file's structs
---@field buf string file text
---@field mode "func"|"type"|"any"
---@field frag string what has already been typed
---@field want_funcs boolean a `func` is being started
---@field range table

--- Shortcuts to put AT THE START of the list (so you don't have to scroll to the last option)
---@param o GoModelOpts
---@return table[]
function M.items(o)
  if o.mode == "type" or not M.is_model_file() then
    return {}
  end
  local mode, frag, buf = o.mode, o.frag, o.buf

  -- `func ` lists the essentials; the standalone shortcuts show up when typed (`short` ≥ 2 letters or `full` ≥ MIN)
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

  -- gorm: TableName() for the structs that don't have it yet
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

  -- model ↔ domain mappers
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
