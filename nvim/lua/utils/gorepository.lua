-- ── Go: the repository port of a domain object (no LLM, 0 tokens) ─────────────
-- Almost every aggregate gets the same persistence port. In a file of the DOMAIN layer (`settings.agent.ddd.layers.domain`: a
-- `domain/`, `entities/`, `model/` folder... read from the path under the module root) type `repository` (`repo` is enough) and each
-- aggregate of the package that has no port yet is offered, written from its fields:
--
--   // Repository is the persistence port of the Note aggregate; infrastructure implements it.
--   type Repository interface {
--       Save(ctx context.Context, note *Note) error
--       FindByID(ctx context.Context, id string) (*Note, error)
--       Delete(ctx context.Context, id string) error
--       List(ctx context.Context) ([]*Note, error)
--   }
--
-- · An aggregate is a struct with an identity: a field `id` (or `ID`, or `NoteID`). Value objects have none and get no repository,
--   nor do `*Model`, `*DTO`, `*Request`, `*Response`, `*Row` or `*Entity` structs (persistence and transport shapes).
-- · The id type is the field's (`string`, `uuid.UUID`, `int64`, `NoteID`...).
-- · In a package named after the struct (`package note`) the port is `Repository` (`note.Repository`); elsewhere `NoteRepository`.
-- · Outside the domain layer, and in persistence models (`*_model.go`), nothing shows up: the port belongs to the domain.
-- · The methods are `settings.go.repository.methods`, in that order (Save FindByID Delete List Exists are known).
-- The adapter is the other half: `func (r *noteRepo) ` in infrastructure offers the methods it is missing (goimpl).
local ix = require "utils.goindex"

local M = {}

local KIND = vim.lsp.protocol.CompletionItemKind
local FORMAT = vim.lsp.protocol.InsertTextFormat

local MIN = 4 -- typed letters (`repo`)
local WORD = "repository"

--- Method name → signature, with `T` the aggregate, `p` its parameter name, `ID` the type of its identity
local METHODS = {
  Save = "Save(ctx context.Context, %p *%T) error",
  FindByID = "FindByID(ctx context.Context, id %ID) (*%T, error)",
  Delete = "Delete(ctx context.Context, id %ID) error",
  List = "List(ctx context.Context) ([]*%T, error)",
  Exists = "Exists(ctx context.Context, id %ID) (bool, error)",
}

---@param word string
---@param frag string
---@return boolean
local function starts(word, frag)
  return word:sub(1, #frag):lower() == frag:lower()
end

--- Is `frag` on its way to showing the item (blink must ask again while the word grows)
---@param frag string
---@return boolean
function M.pending(frag)
  return #frag < MIN and starts(WORD, frag)
end

--- Names of what hangs from an aggregate but is not one: persistence models and transport shapes
local NOT_AGGREGATE = { "Model", "DTO", "Request", "Response", "Row", "Entity" }

---@param struct string
---@return boolean
local function is_aggregate_name(struct)
  return not vim.iter(NOT_AGGREGATE):any(function(suffix)
    return #struct > #suffix and struct:sub(-#suffix) == suffix
  end)
end

--- The type of the identity field of a struct: `id`, `ID`, `Id` or `<Struct>ID`
---@param struct string
---@param fields { name: string, type: string }[]
---@return string?
function M.id_type(struct, fields)
  for _, f in ipairs(fields) do
    local n = f.name:lower()
    if n == "id" or n == struct:lower() .. "id" then
      return f.type
    end
  end
end

--- `Repository` in a package named after the struct, `NoteRepository` otherwise
---@param struct string
---@param pkg_name string?
---@return string
function M.port_name(struct, pkg_name)
  return pkg_name and pkg_name:lower() == struct:lower() and "Repository" or struct .. "Repository"
end

--- The port as source
---@param struct string
---@param id string type of the identity
---@param name string interface name
---@param methods string[] names from METHODS, in order
---@param param string the aggregate's parameter name
---@return string
function M.text(struct, id, name, methods, param)
  local lines = {}
  for _, m in ipairs(methods) do
    local sig = METHODS[m]
    if sig then
      lines[#lines + 1] = "\t" .. sig:gsub("%%ID", id):gsub("%%T", struct):gsub("%%p", param)
    end
  end
  return ("// %s is the persistence port of the %s aggregate; infrastructure implements it.\ntype %s interface {\n%s\n}"):format(
    name,
    struct,
    name,
    table.concat(lines, "\n")
  )
end

--- Is the current file in the domain layer (and not a persistence model)?
---@param path string
---@return boolean
function M.in_domain(path)
  if path == "" or path:match "_model%.go$" then
    return false
  end
  local gomod = vim.fs.find("go.mod", { path = vim.fs.dirname(path), upward = true })[1]
  local base = gomod and vim.fs.dirname(gomod) or vim.uv.cwd()
  local rel = path:sub(1, #base) == base and path:sub(#base + 2) or path
  return require("agent.ddd.layers").of(vim.fs.dirname(rel) or "") == "domain"
end

---@return string[]
local function configured_methods()
  local ok, settings = pcall(require, "core.settings")
  local repo = ok and settings.go and settings.go.repository
  return repo and repo.methods or { "Save", "FindByID", "Delete", "List" }
end

---@param range table
---@param frag string
---@return table[]
function M.declaration_items(range, frag)
  if #frag < MIN or not starts(WORD, frag) then
    return {}
  end
  local pkg, path = ix.current_package()
  if not pkg or not M.in_domain(path) then
    return {}
  end
  local aggregates = {}
  for struct, fields in pairs(pkg.structs) do
    local id = M.id_type(struct, fields)
    if id and is_aggregate_name(struct) and not pkg.interfaces[M.port_name(struct, pkg.name)] then
      aggregates[#aggregates + 1] = { struct = struct, id = id }
    end
  end
  table.sort(aggregates, function(a, b)
    return a.struct < b.struct
  end)
  local param_name = require("utils.gosmart").param_name
  local methods = configured_methods()
  local items = {}
  for _, a in ipairs(aggregates) do
    local name = M.port_name(a.struct, pkg.name)
    items[#items + 1] = {
      label = #aggregates == 1 and "repository" or "repository " .. a.struct,
      labelDetails = { description = ("port of %s → %s"):format(a.struct, name) },
      kind = KIND.Interface,
      insertTextFormat = FORMAT.PlainText,
      filterText = ("repository repo port %s"):format(a.struct),
      sortText = ("%03d"):format(#items + 1),
      textEdit = { newText = M.text(a.struct, a.id, name, methods, param_name(a.struct)), range = range },
    }
  end
  return items
end

return M
