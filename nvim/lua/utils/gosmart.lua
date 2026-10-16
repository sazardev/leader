-- ── Context-aware Go (blink.cmp source + filters) ──────────────────────────────
-- Reads the treesitter tree to know WHERE the cursor is and offer only what
-- applies, with readable names (no acronyms):
--   start of declaration → `func` variants, methods of EVERY struct in the
--                          file, `NewX(fields…)` for structs without a
--                          constructor, and `type` variants
--   type Envelope |       → struct { } / interface { } / func(…)
--   inside interface      → method signatures (error, ctx, result…)
--   snippets (json)       → declarations only at package level, statements
--                           only inside functions
--   noise                 → no buffer words or the LSP's generic `func`/`type`
--                           show up there
local M = {}

local KIND = vim.lsp.protocol.CompletionItemKind
local FORMAT = vim.lsp.protocol.InsertTextFormat

local FUNC_NODES = { function_declaration = true, method_declaration = true, func_literal = true }

---@param row integer 1-indexed
---@param col integer 0-indexed
---@return TSNode?
local function node_at(row, col)
  local ok, node = pcall(function()
    vim.treesitter.get_parser(0, "go"):parse()
    return vim.treesitter.get_node { pos = { row - 1, math.max(col - 1, 0) } }
  end)
  return ok and node or nil
end

local last = { key = "", scope = "other" }

--- "top" (package level) | "func" (function body) | "struct" | "interface" | "other"
---@param row integer
---@param col integer
---@param line string
---@return "top"|"func"|"struct"|"interface"|"other"
function M.scope(row, col, line)
  -- several sources ask about the same keystroke: computed once
  local key = ("%d:%d:%d:%d"):format(vim.api.nvim_get_current_buf(), vim.b.changedtick or 0, row, col)
  if key == last.key then
    return last.scope
  end
  local scope = "other"
  local node = node_at(row, col)
  local in_block = false
  while node do
    local t = node:type()
    if t == "block" then
      in_block = true
    elseif FUNC_NODES[t] then
      scope = in_block and "func" or "other" -- no block: you're in the signature
      break
    elseif t == "field_declaration_list" then
      scope = "struct"
      break
    elseif t == "interface_type" then
      scope = "interface"
      break
    elseif t == "source_file" then
      -- a broken tree can leave indented code as "top": no filtering there
      scope = line:find "^%s" and "other" or "top"
      break
    end
    node = node:parent()
  end
  last = { key = key, scope = scope }
  return scope
end

---@param ctx blink.cmp.Context
---@return "func"|"type"|"any"? mode # which declaration is being started (nil = something else)
---@return string? frag # what has already been typed of the word (after `func `/`type ` or at line start)
local function decl_start(ctx)
  local row, col = ctx.cursor[1], ctx.cursor[2]
  local before = ctx.line:sub(1, col)
  local mode, frag
  local word, rest = before:match "^(%a+)%s+([%w_]*)$"
  if word == "func" or word == "type" then
    mode, frag = word, rest
  elseif before:match "^[%w_]*$" then
    mode, frag = "any", before
  end
  if mode and M.scope(row, col, ctx.line) == "top" then
    return mode, frag
  end
end

-- ── preview (blink's documentation window) ────────────────────────────────────
---@param item table
---@return string
local function preview_text(item)
  local text = item.textEdit and item.textEdit.newText or item.insertText or item.label
  if item.insertTextFormat == FORMAT.Snippet then
    local ok, parsed = pcall(vim.lsp._snippet_grammar.parse, text)
    if ok and parsed then
      return tostring(parsed) -- placeholders replaced by their default values
    end
  end
  return text
end

--- A source's `resolve`: shows in the docs window what is about to be inserted
---@param item table
---@param callback fun(item: table)
function M.resolve(item, callback)
  local resolved = vim.deepcopy(item)
  resolved.documentation = { kind = "markdown", value = "```go\n" .. preview_text(item) .. "\n```" }
  callback(resolved)
end

-- ── text helpers ───────────────────────────────────────────────────────────────
local GO_KEYWORDS = {}
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
} do
  GO_KEYWORDS[kw] = true
end

--- UserID → userID, ID → id, HTTPServer → httpServer
---@param name string
---@return string
local function param_name(name)
  local p = name:gsub("^(%u+)(%u%l)", function(a, b)
    return a:lower() .. b
  end)
  p = p:match "^%u+$" and p:lower() or p:gsub("^%u", string.lower)
  return GO_KEYWORDS[p] and p .. "_" or p
end

M.param_name = param_name

---@class GoStruct
---@field name string
---@field fields { name: string, type: string }[]

---@param root TSNode
---@param source integer|string buffer or text `root` comes from
---@return GoStruct[]
local function structs_from(root, source)
  local function text(n)
    return vim.treesitter.get_node_text(n, source)
  end
  local found = {}
  for decl in root:iter_children() do
    if decl:type() == "type_declaration" then
      for spec in decl:iter_children() do
        local name, typ = spec:field("name")[1], spec:field("type")[1]
        if spec:type() == "type_spec" and name and typ and typ:type() == "struct_type" then
          local s = { name = text(name), fields = {} }
          for _, list in ipairs(typ:named_children()) do
            for _, field in ipairs(list:named_children()) do
              local ftype = field:field("type")[1]
              -- embedded fields (unnamed) are skipped
              if field:type() == "field_declaration" and ftype and #field:field "name" > 0 then
                for _, fname in ipairs(field:field "name") do
                  s.fields[#s.fields + 1] = { name = text(fname), type = text(ftype) }
                end
              end
            end
          end
          found[#found + 1] = s
        end
      end
    end
  end
  return found
end

--- `type Kind string` → { Kind = "string" } (structs are handled separately)
---@param root TSNode
---@param source integer|string
---@return table<string, string>
local function named_types_from(root, source)
  local out = {}
  for decl in root:iter_children() do
    if decl:type() == "type_declaration" then
      for spec in decl:iter_children() do
        local name, typ = spec:field("name")[1], spec:field("type")[1]
        if spec:type() == "type_spec" and name and typ and typ:type() ~= "struct_type" then
          out[vim.treesitter.get_node_text(name, source)] = vim.treesitter.get_node_text(typ, source)
        end
      end
    end
  end
  return out
end

---@return TSNode?
local function buffer_root()
  local ok, parser = pcall(vim.treesitter.get_parser, 0, "go")
  if ok and parser then
    return parser:parse()[1]:root()
  end
end

---@return GoStruct[]
local function structs_in_buffer()
  local root = buffer_root()
  return root and structs_from(root, 0) or {}
end

---@param root TSNode
---@param source integer|string
---@return string?
local function package_name(root, source)
  for node in root:iter_children() do
    if node:type() == "package_clause" and node:named_child(0) then
      return vim.treesitter.get_node_text(node:named_child(0), source)
    end
  end
end

-- structs from the package's other files, cached by modification time
local file_cache = {}

---@param current string path of the current buffer
---@param pkg string
---@return GoStruct[] structs, table<string, string> types
local function sibling_structs(current, pkg)
  local dir, out, types, seen = vim.fs.dirname(current), {}, {}, 0
  for name, kind in vim.fs.dir(dir) do
    local path = dir .. "/" .. name
    if kind == "file" and name:match "%.go$" and path ~= current and seen < 300 then
      seen = seen + 1
      local stat = vim.uv.fs_stat(path)
      local stamp = stat and ("%d.%d"):format(stat.mtime.sec, stat.mtime.nsec) or ""
      local entry = file_cache[path]
      if not entry or entry.stamp ~= stamp then
        entry = { stamp = stamp, structs = {}, types = {} }
        local f = io.open(path, "r")
        local text = f and f:read "*a"
        if f then
          f:close()
        end
        local ok, parser = pcall(vim.treesitter.get_string_parser, text or "", "go")
        if ok and text then
          local root = parser:parse()[1]:root()
          entry.pkg, entry.structs = package_name(root, text), structs_from(root, text)
          entry.types = named_types_from(root, text)
        end
        file_cache[path] = entry
      end
      if entry.pkg == pkg then
        vim.list_extend(out, entry.structs)
        types = vim.tbl_extend("keep", types, entry.types)
      end
    end
  end
  return out, types
end

local package_types_cache = {}

--- Structs that can be filled in: the buffer's + the rest of the package's
--- (same directory and same `package`). Those from other packages are completed by gopls.
---@return GoStruct[]
local function package_structs()
  local list = structs_in_buffer()
  local path = vim.api.nvim_buf_get_name(0)
  local root = buffer_root()
  local pkg = root and path ~= "" and package_name(root, 0)
  if not pkg then
    package_types_cache = root and named_types_from(root, 0) or {}
    return list
  end
  local names = {}
  for _, s in ipairs(list) do
    names[s.name] = true
  end
  local siblings, types = sibling_structs(path, pkg)
  for _, s in ipairs(siblings) do
    if not names[s.name] then
      names[s.name] = true
      list[#list + 1] = s
    end
  end
  local own = named_types_from(root, 0)
  package_types_cache = vim.tbl_extend("keep", own, types)
  return list
end

--- Defined types of the package (`Kind` → `string`), after the last call to package_structs()
---@return table<string, string>
local function package_types()
  return package_types_cache
end

---@param s GoStruct
---@return string
local function constructor_text(s)
  local params, assigns = {}, {}
  for _, f in ipairs(s.fields) do
    local p = param_name(f.name)
    params[#params + 1] = ("%s %s"):format(p, f.type)
    assigns[#assigns + 1] = ("\t\t%s: %s,"):format(f.name, p)
  end
  local head = ("func New%s(%s) *%s {"):format(s.name, table.concat(params, ", "), s.name)
  if #assigns == 0 then
    return ("%s\n\treturn &%s{}\n}"):format(head, s.name)
  end
  return ("%s\n\treturn &%s{\n%s\n\t}\n}"):format(head, s.name, table.concat(assigns, "\n"))
end

local FUNCNEW_MIN = 5 -- typed letters (`funcn`) for `funcnew` to show up

--- Escape what the LSP snippet parser interprets (`$`, `}` and `\`)
---@param text string
---@return string
local function snippet_escape(text)
  return (text:gsub("[$}\\]", "\\%0"))
end

--- `time.Time` fields born with the object (createdAt, updatedAt, modifiedAt…): they aren't
--- parameters, they're filled with a single `now`. Other `time.Time` fields (dueDate…) are parameters.
---@param f { name: string, type: string }
---@return boolean
local function is_now_field(f)
  local n = f.name:lower()
  return f.type == "time.Time" and (n:find "^created" or n:find "^updated" or n:find "^modified") ~= nil
end

--- `New` (or `NewX` if there are several structs) with the fields and `(*X, error)`.
--- Contiguous parameters of the same type are grouped: `id, title, content string`.
--- Creation/update `time.Time` fields come from `now := time.Now().UTC()`.
--- `$0` lands before the return, for validations.
---@param s GoStruct
---@param single boolean # only struct in the file → `New`
---@return string
local function constructor_error_text(s, single)
  local groups, assigns, width, uses_now = {}, {}, 0, false
  for _, f in ipairs(s.fields) do
    width = math.max(width, #f.name)
    if is_now_field(f) then
      uses_now = true
    else
      local p = param_name(f.name)
      local g = groups[#groups]
      if g and g.type == f.type then
        g.names[#g.names + 1] = p
      else
        groups[#groups + 1] = { names = { p }, type = f.type }
      end
    end
  end
  local params = {}
  for i, g in ipairs(groups) do
    params[i] = ("%s %s"):format(table.concat(g.names, ", "), g.type)
  end
  for _, f in ipairs(s.fields) do
    local pad = (" "):rep(width - #f.name)
    local value = is_now_field(f) and "now" or param_name(f.name)
    assigns[#assigns + 1] = ("\t\t%s:%s %s,"):format(f.name, pad, value)
  end
  local name = single and "New" or "New" .. s.name
  local head = ("func %s(%s) (*%s, error) {"):format(name, table.concat(params, ", "), s.name)
  local body = (uses_now and "\n\tnow := time.Now().UTC()" or "")
    .. (#assigns == 0 and ("\n\treturn &%s{}, nil"):format(s.name) or ("\n\treturn &%s{\n%s\n\t}, nil"):format(
      s.name,
      table.concat(assigns, "\n")
    ))
  return snippet_escape(head .. "\n\t") .. "$0" .. snippet_escape(body .. "\n}")
end

-- ── templates ─────────────────────────────────────────────────────────────────
-- { label, description, body (LSP snippet) }
local FUNCS = {
  { "func", "function", "func ${1:name}(${2}) {\n\t$0\n}" },
  { "func error", "→ error", "func ${1:name}(${2}) error {\n\t$0\n\treturn nil\n}" },
  { "func value", "→ T", 'func ${1:name}(${2}) ${3:string} {\n\t$0\n\treturn ${4:""}\n}' },
  { "func pointer", "→ *T", "func ${1:name}(${2}) *${3:Thing} {\n\t$0\n\treturn &$3{}\n}" },
  { "func bool", "→ bool", "func ${1:name}(${2}) bool {\n\t$0\n\treturn ${3:false}\n}" },
  {
    "func result error",
    "→ (T, error)",
    'func ${1:name}(${2}) (${3:string}, error) {\n\t$0\n\treturn ${4:""}, nil\n}',
  },
  {
    "func pointer error",
    "→ (*T, error)",
    "func ${1:name}(${2}) (*${3:Thing}, error) {\n\t$0\n\treturn &$3{}, nil\n}",
  },
  { "func ctx error", "(ctx) → error", "func ${1:name}(ctx context.Context${2}) error {\n\t$0\n\treturn nil\n}" },
  {
    "func ctx result error",
    "(ctx) → (T, error)",
    'func ${1:name}(ctx context.Context${2}) (${3:string}, error) {\n\t$0\n\treturn ${4:""}, nil\n}',
  },
  { "func main", "entry point", "func main() {\n\t$0\n}" },
  { "func init", "init()", "func init() {\n\t$0\n}" },
}

local TYPES = {
  { "type struct", "struct", "type ${1:Name} struct {\n\t$0\n}" },
  {
    "type struct constructor",
    "struct + NewX",
    "type ${1:Name} struct {\n\t${2:Field} ${3:string}\n}\n\nfunc New$1(${4:field} $3) *$1 {\n\treturn &$1{$2: $4}\n}",
  },
  { "type generic struct", "struct[T]", "type ${1:Set}[${2:T} ${3:comparable}] struct {\n\t$0\n}" },
  { "type interface", "interface", "type ${1:Name} interface {\n\t$0\n}" },
  { "type interface method", "interface with method", "type ${1:Name} interface {\n\t${2:Do}(${3}) ${4:error}\n}" },
  {
    "type interface ctx result error",
    "interface (ctx) → (T, error)",
    "type ${1:Service} interface {\n\t${2:Get}(ctx context.Context, ${3:id string}) (${4:*Thing}, error)\n}",
  },
  {
    "type enum string",
    "string + constants",
    'type ${1:Kind} string\n\nconst (\n\t$1${2:A} $1 = "${3:a}"\n\t$1${4:B} $1 = "${5:b}"\n)',
  },
  { "type enum iota", "int + iota", "type ${1:Kind} int\n\nconst (\n\t${2:A} $1 = iota\n\t${3:B}\n\t${4:C}\n)" },
  { "type defined", "type Name string", "type ${1:Name} ${2:string}" },
  { "type func", "func(…) …", "type ${1:Handler} func(${2}) ${3:error}" },
  {
    "type error",
    "custom error",
    "type ${1:Name}Error struct {\n\t${2:Msg} string\n}\n\nfunc (e *$1Error) Error() string { return e.$2 }",
  },
  {
    "type options",
    "functional options",
    "type ${1:Option} func(*${2:Config})\n\nfunc With${3:Name}(v ${4:string}) $1 {\n\treturn func(c *$2) { c.$3 = v }\n}",
  },
}

-- inside `interface { }`
local METHODS = {
  { "method", "Do()", "${1:Do}(${2})" },
  { "method error", "→ error", "${1:Do}(${2}) error" },
  { "method value", "→ T", "${1:Name}(${2}) ${3:string}" },
  { "method result error", "→ (T, error)", "${1:Get}(${2}) (${3:string}, error)" },
  { "method ctx error", "(ctx) → error", "${1:Do}(ctx context.Context${2}) error" },
  { "method ctx result error", "(ctx) → (T, error)", "${1:Get}(ctx context.Context${2}) (${3:*Thing}, error)" },
  { "embed interface", "io.Reader…", "${1:io.Reader}" },
}

---@param label string
---@param detail string
---@param text string
---@param order integer
---@param range table
---@param filter? string
local function snippet_item(label, detail, text, order, range, filter)
  return {
    label = label,
    labelDetails = { description = detail },
    kind = KIND.Snippet,
    insertTextFormat = FORMAT.Snippet,
    filterText = filter or label,
    sortText = ("%03d"):format(order),
    textEdit = { newText = text, range = range },
  }
end

---@param templates table[]
---@param items table[]
---@param range table
local function add_templates(templates, items, range)
  for _, t in ipairs(templates) do
    items[#items + 1] = snippet_item(t[1], t[2], t[3], #items + 1, range)
  end
end

--- Does `word` start with what was typed? (case-insensitive; empty = yes)
---@param word string
---@param frag string
local function starts(word, frag)
  return frag == "" or word:lower():sub(1, #frag) == frag:lower()
end

--- Helpers based on already-written code for a new declaration (0 tokens): goimpl, goenum, gomap, gohttp
---@param range table
---@param frag string
---@return table[]
function M.extra_declaration_items(range, frag)
  local items = {}
  for _, name in ipairs { "goimpl", "goenum", "gomap", "gohttp" } do
    vim.list_extend(items, require("utils." .. name).declaration_items(range, frag))
  end
  for _, item in ipairs(items) do
    item.sortText = "!" .. (item.sortText or "") -- "!" sorts before digits: above templates and constructors
  end
  return items
end

--- Helpers (utils/<name>.lua: `declaration_items(range, frag)` and `pending(frag)`) whose items exist only once their word is typed
local TYPED_HELPERS = { "goreconstitute", "gogetters", "gorepository" }

-- STRICT prefix filter (not fuzzy): `pac` must not bring anything from `type`.
--   func family  → `f`, `fu`, `func`, or after `func ` with nothing else
--   type family  → `t`, `ty`, `type`, or after `type ` with nothing else
--   constructor  → `New…` or the struct's name (`Env…`), and after `func Ne…`
--   funcnew      → (only when typed) `New(all the fields) (*X, error)`
--   reconstitute → (only when typed, `recon`) `Reconstitute(all the fields) *X`, see utils/goreconstitute.lua
--   getters      → (only when typed, `gette`) the accessors of the private fields, see utils/gogetters.lua
--   repository   → (only when typed, `repo`, in the domain layer) the persistence port of an aggregate, see utils/gorepository.lua
--   after `type Foo` / `func Foo` something is being NAMED: nothing else shows up
---@param ctx blink.cmp.Context
---@param mode "func"|"type"|"any"
---@param frag string
---@return table[]
local function declaration_items(ctx, mode, frag)
  local row, col = ctx.cursor[1], ctx.cursor[2]
  local indent = #ctx.line:match "^%s*"
  local range = {
    start = { line = row - 1, character = indent },
    ["end"] = { line = row - 1, character = col },
  }
  local items = {}
  local buf = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  local want_funcs = (mode == "func" and frag == "") or (mode == "any" and starts("func", frag))
  local want_types = (mode == "type" and frag == "") or (mode == "any" and starts("type", frag))

  if want_funcs then
    add_templates(FUNCS, items, range)
  end
  -- *_model.go files: functable, funcdomain, functodomain, funcfromdomain (see utils/gomodel.lua).
  -- They go BEFORE the rest of the `func…` items so you don't have to scroll to the last option.
  -- helpers based on already-written code (0 tokens), also AT THE START: missing methods for an interface (goimpl), enum
  -- helpers (goenum), mappers between structs (gomap) and a service's handlers (gohttp)
  if want_funcs then
    for i, item in ipairs(M.extra_declaration_items(range, mode == "func" and "" or frag)) do
      table.insert(items, i, item)
    end
  end
  -- `var _ I = (*T)(nil)` for the structs already recognised as an implementation (goport)
  if mode == "any" and frag ~= "" and starts("var", frag) then
    for i, item in ipairs(require("utils.goport").declaration_items(range, frag)) do
      table.insert(items, i, item)
    end
  end
  -- helpers that only show up when their word is typed (≥ their minimum) go first: `Reconstitute`, the getters, the repository
  if mode == "any" and frag ~= "" then
    for _, name in ipairs(TYPED_HELPERS) do
      for i, item in ipairs(require("utils." .. name).declaration_items(range, frag)) do
        table.insert(items, i, item)
      end
    end
  end
  for i, item in ipairs(require("utils.gomodel").items {
    structs = structs_in_buffer(),
    buf = buf,
    mode = mode,
    frag = frag,
    want_funcs = want_funcs,
    range = range,
  }) do
    table.insert(items, i, item)
  end
  if mode ~= "type" then
    for _, s in ipairs(structs_in_buffer()) do
      local r = s.name:sub(1, 1):lower()
      local recv = GO_KEYWORDS[r] and r .. "_" or r
      local function method(label, detail, text)
        items[#items + 1] =
          snippet_item(label, detail, text, #items + 1, range, ("func method %s %s"):format(s.name, label))
      end
      if want_funcs then
        method(
          ("func (%s *%s)"):format(recv, s.name),
          "method",
          ("func (%s *%s) ${1:Name}(${2}) {\n\t$0\n}"):format(recv, s.name)
        )
        method(
          ("func (%s *%s) error"):format(recv, s.name),
          "method → error",
          ("func (%s *%s) ${1:Name}(${2}) error {\n\t$0\n\treturn nil\n}"):format(recv, s.name)
        )
        method(
          ("func (%s %s)"):format(recv, s.name),
          "method (value receiver)",
          ("func (%s %s) ${1:Name}(${2}) ${3:string} {\n\t$0\n}"):format(recv, s.name)
        )
        method(
          ("func (%s %s) String"):format(recv, s.name),
          "fmt.Stringer",
          ("func (%s %s) String() string {\n\t$0\n}"):format(recv, s.name)
        )
      end
      local wants_ctor = (mode == "func" and frag == "")
        or (frag ~= "" and (starts("New" .. s.name, frag) or starts(s.name, frag)))
        or (mode == "any" and frag == "")
      if wants_ctor and not buf:find("func New" .. s.name .. "%(") then
        items[#items + 1] = {
          label = "New" .. s.name,
          labelDetails = { description = "constructor" },
          kind = KIND.Function,
          insertTextFormat = FORMAT.PlainText,
          filterText = ("func New%s %s constructor"):format(s.name, s.name),
          sortText = ("%03d"):format(#items + 1),
          textEdit = { newText = constructor_text(s), range = range },
        }
      end
    end
  end
  -- `funcnew`: constructor with all the fields → (*X, error). Only if you type it (≥ `funcn`)
  if mode == "any" and #frag >= FUNCNEW_MIN and starts("funcnew", frag) then
    local structs = structs_in_buffer()
    for _, s in ipairs(structs) do
      local single = #structs == 1
      items[#items + 1] = {
        label = single and "funcnew" or "funcnew " .. s.name,
        labelDetails = { description = ("→ (*%s, error)"):format(s.name) },
        kind = KIND.Snippet,
        insertTextFormat = FORMAT.Snippet,
        filterText = single and "funcnew" or "funcnew " .. s.name,
        sortText = ("%03d"):format(#items + 1),
        textEdit = { newText = constructor_error_text(s, single), range = range },
      }
    end
  end
  if want_types then
    add_templates(TYPES, items, range)
  end
  return items
end

-- ── inside `Envelope{ }`: missing fields ────────────────────────────────────────
-- Only structs declared in the same file (gopls completes the rest).
local ZERO_VALUES = {
  string = '""',
  bool = "false",
  error = "nil",
  any = "nil",
}
for _, n in ipairs {
  "int",
  "int8",
  "int16",
  "int32",
  "int64",
  "uint",
  "uint8",
  "uint16",
  "uint32",
  "uint64",
  "uintptr",
  "float32",
  "float64",
  "byte",
  "rune",
} do
  ZERO_VALUES[n] = "0"
end

---@param node TSNode?
---@return string?
local function type_name(node)
  if not node then
    return nil
  end
  if node:type() == "type_identifier" then
    return vim.treesitter.get_node_text(node, 0)
  elseif node:type() == "pointer_type" then
    return type_name(node:named_child(0))
  end
end

--- Type name of a literal: `Envelope{`, `&Envelope{` or the elided element of `[]Envelope{ {…} }`
---@param lv TSNode literal_value
---@return string?
local function literal_type(lv)
  local parent = lv:parent()
  if not parent then
    return nil
  end
  if parent:type() == "composite_literal" then
    return type_name(parent:field("type")[1])
  end
  if parent:type() == "literal_element" then
    local comp = parent:parent() and parent:parent():parent()
    local t = comp and comp:type() == "composite_literal" and comp:field("type")[1]
    if t then
      return type_name(t:field("element")[1] or t:field("value")[1])
    end
  end
end

-- what you can NOT pass through when climbing: you're inside another element's value
local INSIDE_VALUE = { keyed_element = true, argument_list = true, call_expression = true }

---@class GoLiteral
---@field struct GoStruct
---@field missing { name: string, type: string }[]
---@field inline boolean `T{|}` on a single line: the lines have to be opened

--- Are you starting a new element inside a literal of a known struct?
---@param ctx { line: string, cursor: integer[] }
---@return GoLiteral?
local function compute_literal(ctx)
  local row, col = ctx.cursor[1], ctx.cursor[2]
  local before, after = ctx.line:sub(1, col), ctx.line:sub(col + 1)
  -- `Envelope{|}` on a single line (mini.pairs or on accepting `Envelope{}`) or a new element
  local inline = before:match "{%s*$" ~= nil and after:match "^%s*}" ~= nil
  if not (inline or before:match "^%s*[%w_]*$") then
    return nil
  end
  local node = node_at(row, col)
  while node and node:type() ~= "literal_value" do
    if INSIDE_VALUE[node:type()] or node:type() == "block" then
      return nil
    end
    node = node:parent()
  end
  if not node then
    return nil
  end
  local name = literal_type(node)
  if not name then
    return nil
  end
  local struct
  for _, s in ipairs(package_structs()) do
    if s.name == name then
      struct = s
    end
  end
  if not struct then
    return nil
  end
  local present = {}
  for child in node:iter_children() do
    if child:type() == "keyed_element" then
      present[vim.treesitter.get_node_text(child:field("key")[1], 0)] = true
    elseif child:type() == "literal_element" and child:start() ~= row - 1 then
      return nil -- positional literal (`T{a, b}`): keys aren't mixed in
    end
  end
  local missing = {}
  for _, f in ipairs(struct.fields) do
    if not present[f.name] then
      missing[#missing + 1] = f
    end
  end
  if #missing == 0 then
    return nil
  end
  return { struct = struct, missing = missing, inline = inline }
end

local literal_memo = { key = "" }

--- several sources ask about the same keystroke: computed once
---@param ctx { line: string, cursor: integer[] }
---@return GoLiteral?
local function literal_info(ctx)
  local key = ("%d:%d:%d:%d"):format(
    vim.api.nvim_get_current_buf(),
    vim.b.changedtick or 0,
    ctx.cursor[1],
    ctx.cursor[2]
  )
  if literal_memo.key ~= key then
    literal_memo = { key = key, value = compute_literal(ctx) }
  end
  return literal_memo.value
end

---@param known table<string, boolean> names of the package's structs
---@param types? table<string, string> defined types (`Kind` → `string`)
---@return fun(t: string): string
local function zero_value_for(known, types)
  local function zero(t, depth)
    if ZERO_VALUES[t] then
      return ZERO_VALUES[t]
    elseif t == "time.Time" then
      return "time.Time{}"
    elseif t == "time.Duration" then
      return "0"
    elseif known[t] then
      return t .. "{}"
    elseif t:match "^[%*%[]" or t:match "^map%[" or t:match "^chan%s" or t:match "^func" or t:match "^interface" then
      return "nil"
    elseif types and types[t] and depth < 3 then
      return zero(types[t], depth + 1) -- `type Kind string` → ""
    end
    return ""
  end
  return function(t)
    return zero(t, 0)
  end
end

---@param structs GoStruct[]
---@return table<string, boolean>
local function names_of(structs)
  local known = {}
  for _, s in ipairs(structs) do
    known[s.name] = true
  end
  return known
end

-- Careful: vim.snippet already adds the current line's indentation to each new line
-- of the snippet, so only the RELATIVE indentation (`\t`) is used here.
---@param ctx blink.cmp.Context
---@param lit GoLiteral
---@return table[]
local function literal_items(ctx, lit)
  local row, col = ctx.cursor[1], ctx.cursor[2]
  local indent = ctx.line:match "^%s*"
  -- new line: what was typed is replaced; `T{|}`: the lines around the cursor are opened
  local range = {
    start = { line = row - 1, character = lit.inline and col or #indent },
    ["end"] = { line = row - 1, character = col },
  }
  local function wrap(text)
    return lit.inline and ("\n\t%s\n"):format(text) or text
  end
  local zero = zero_value_for(names_of(package_structs()), package_types())

  local items, lines = {}, {}
  for i, f in ipairs(lit.missing) do
    items[#items + 1] = {
      label = f.name,
      labelDetails = { description = f.type },
      kind = KIND.Field,
      insertTextFormat = FORMAT.Snippet,
      filterText = f.name,
      sortText = ("%03d"):format(i + 1),
      textEdit = { newText = wrap(("%s: ${1:%s},"):format(f.name, zero(f.type))), range = range },
    }
    lines[#lines + 1] = ("%s: ${%d:%s},"):format(f.name, i, zero(f.type))
  end
  if #lit.missing > 1 then
    table.insert(items, 1, {
      label = "fill all fields",
      labelDetails = { description = ("%d missing"):format(#lit.missing) },
      kind = KIND.Snippet,
      insertTextFormat = FORMAT.Snippet,
      filterText = "fill all fields",
      sortText = "000",
      -- Tab jumps from value to value
      textEdit = { newText = wrap(table.concat(lines, lit.inline and "\n\t" or "\n")), range = range },
    })
  end
  return items
end

-- ── `x := Env|` → the struct ALREADY filled in on accept ───────────────────────
-- In a VALUE position (right side of `:=`/`=`, `return`, `Field: `, call argument)
-- the name of a package struct is offered as a full literal:
-- Enter inserts `Envelope{ Kind: …, ID: … }` with Tab jumping from value to value.
-- In a TYPE position (`var e Envelope`, parameters, `[]Envelope`, `new(Envelope)`)
-- it doesn't apply and gopls' normal completion follows.
---@param ctx blink.cmp.Context
---@return string? frag
local function value_position(ctx)
  local before = ctx.line:sub(1, ctx.cursor[2])
  local frag = before:match ":=%s*&?([%w_]*)$"
    or before:match "[^=!<>:]=%s*&?([%w_]*)$"
    or before:match "^%s*return%s+&?([%w_]*)$"
    or before:match "[%w_]:%s+&?([%w_]*)$"
  if not frag and not before:match "^%s*var%s+[^=]*$" then
    frag = before:match "[%w_.]%(%s*&?([%w_]*)$" or before:match ",%s*&?([%w_]*)$"
  end
  if not frag or frag == "" or before:match "new%(%s*&?[%w_]*$" or before:match "make%(%s*[%w_]*$" then
    return nil
  end
  if M.scope(ctx.cursor[1], ctx.cursor[2], ctx.line) == "func" then
    return frag
  end
end

local value_memo = { key = "" }

---@param ctx blink.cmp.Context
---@return { frag: string, structs: GoStruct[] }?
local function value_info(ctx)
  local key = ("%d:%d:%d:%d"):format(
    vim.api.nvim_get_current_buf(),
    vim.b.changedtick or 0,
    ctx.cursor[1],
    ctx.cursor[2]
  )
  if value_memo.key ~= key then
    local info
    local frag = value_position(ctx)
    if frag then
      local structs = vim.tbl_filter(function(s)
        return starts(s.name, frag)
      end, package_structs())
      info = #structs > 0 and { frag = frag, structs = structs } or nil
    end
    value_memo = { key = key, value = info }
  end
  return value_memo.value
end

---@param ctx blink.cmp.Context
---@param info { frag: string, structs: GoStruct[] }
---@return table[]
local function struct_literal_items(ctx, info)
  local row, col = ctx.cursor[1], ctx.cursor[2]
  local zero = zero_value_for(names_of(package_structs()), package_types())
  local range = {
    start = { line = row - 1, character = col - #info.frag },
    ["end"] = { line = row - 1, character = col },
  }
  local items = {}
  for i, s in ipairs(info.structs) do
    local text = s.name .. "{}"
    if #s.fields > 0 then
      local lines = {}
      for n, f in ipairs(s.fields) do
        lines[n] = ("%s: ${%d:%s},"):format(f.name, n, zero(f.type))
      end
      text = ("%s{\n\t%s\n}"):format(s.name, table.concat(lines, "\n\t"))
    end
    items[#items + 1] = {
      label = s.name,
      labelDetails = { description = ("literal, %d fields"):format(#s.fields) },
      kind = KIND.Struct,
      insertTextFormat = FORMAT.Snippet,
      filterText = s.name,
      sortText = ("%03d"):format(i),
      textEdit = { newText = text, range = range },
    }
  end
  return items
end

-- ── `type Name |` → body ─────────────────────────────────────────────────────
local function type_body_items(before)
  if not before:match "^type%s+[%w_]+%s+[%w_]*$" then
    return {}
  end
  local function body(word, order, text, detail)
    return {
      label = word,
      labelDetails = { description = detail },
      kind = KIND.Keyword,
      insertText = text,
      insertTextFormat = FORMAT.Snippet,
      filterText = word,
      sortText = order,
    }
  end
  return {
    body("struct", "01", "struct {\n\t$0\n}", "{ … }"),
    body("interface", "02", "interface {\n\t$0\n}", "{ … }"),
    body("func", "03", "func(${1}) ${2:error}", "func(…)"),
  }
end

-- ── inside `interface { }` ────────────────────────────────────────────────────
local function interface_items(ctx)
  local col = ctx.cursor[2]
  if not ctx.line:sub(1, col):match "^%s*[%w_.]*$" then
    return {}
  end
  local range = {
    start = { line = ctx.cursor[1] - 1, character = #ctx.line:match "^%s*" },
    ["end"] = { line = ctx.cursor[1] - 1, character = col },
  }
  local items = {}
  add_templates(METHODS, items, range)
  return items
end

-- ── user snippets: filter by context ───────────────────────────────────────────
local function set(list)
  local s = {}
  for _, v in ipairs(list) do
    s[v] = true
  end
  return s
end

-- declarations: package level only
local TOP_ONLY = set {
  "errorsentinel",
  "testtable",
  "testhelper",
  "httphandlerjson",
  "embed",
  -- friendly-snippets
  "func",
  "tyf",
  "tyi",
  "tys",
  "pkgm",
  "im",
  "ims",
  "co",
  "cos",
  "finit",
  "fmain",
  "tf",
  "tm",
  "bf",
  "ef",
  "tdt",
  "hand",
  "helloweb",
  "sort",
  "meth",
  "fum",
}
-- statements: only inside a function
local FUNC_ONLY = set {
  "iferr",
  "errorsis",
  "errorsas",
  "contexttimeout",
  "contextcancel",
  "waitgroup",
  "errgroup",
  "mutex",
  "once",
  "selectcontext",
  "forrangeindex",
  "forrangeint",
  "testsubtest",
  "jsondecodebody",
  "slog",
  "deferfunc",
  -- friendly-snippets
  "if",
  "el",
  "ife",
  "ir",
  "for",
  "fori",
  "forr",
  "switch",
  "sel",
  "cs",
  "go",
  "gf",
  "df",
  "lp",
  "lf",
  "lv",
  "fp",
  "ff",
  "tl",
  "tlf",
  "tlv",
  "pn",
  "rd",
  "herr",
  "las",
  "sv",
  "om",
}
-- friendly-snippets now covered by gosmart (with more variants and no acronyms)
local SUPERSEDED = set { "func", "fum", "meth", "tyf", "tyi", "tys", "finit", "fmain" }

---@param ctx blink.cmp.Context
---@param items blink.cmp.CompletionItem[]
---@return blink.cmp.CompletionItem[]
function M.filter_snippets(ctx, items)
  if vim.bo.filetype ~= "go" then
    return items
  end
  if require("utils.goimpl").method_position(ctx.line, ctx.cursor[2]) or require("utils.goiferr").fresh(ctx) then
    return {} -- after `func (s *T) ` a method is only being named; after `x, err := …`, only the `if err != nil`
  end
  local scope = M.scope(ctx.cursor[1], ctx.cursor[2], ctx.line)
  return vim.tbl_filter(function(it)
    local label = it.label
    if scope == "top" then
      return not (FUNC_ONLY[label] or SUPERSEDED[label])
    elseif scope == "func" then
      return not TOP_ONLY[label]
    elseif scope == "struct" or scope == "interface" then
      return not (TOP_ONLY[label] or FUNC_ONLY[label])
    end
    return true
  end, items)
end

-- ── noise from other sources ───────────────────────────────────────────────────
--- When starting a declaration: no stray buffer words (e.g. "ID").
---@param ctx blink.cmp.Context
---@param items blink.cmp.CompletionItem[]
function M.quiet_buffer(ctx, items)
  if vim.bo.filetype ~= "go" then
    return items
  end
  if
    decl_start(ctx)
    or M.scope(ctx.cursor[1], ctx.cursor[2], ctx.line) == "interface"
    or literal_info(ctx)
    or require("utils.goimpl").method_position(ctx.line, ctx.cursor[2])
    or require("utils.goiferr").fresh(ctx)
  then
    return {}
  end
  local value = value_info(ctx)
  if value then -- without the same stray name from the buffer
    local mine = names_of(value.structs)
    return vim.tbl_filter(function(it)
      return not mine[it.label]
    end, items)
  end
  return items
end

--- When starting a declaration: without the LSP's generic `func`/`type` (the variants already show up).
---@param ctx blink.cmp.Context
---@param items blink.cmp.CompletionItem[]
function M.quiet_lsp(ctx, items)
  if vim.bo.filetype ~= "go" then
    return items
  end
  -- `package …` at the top of a file: `main` only where it makes sense, the folder's own package first (gopackage)
  if ctx.line:sub(1, ctx.cursor[2]):match "^p%a*%s*[%w_]*$" then
    items = require("utils.gopackage").transform(ctx, items)
  end
  if decl_start(ctx) then
    return vim.tbl_filter(function(it)
      return not (it.kind == KIND.Keyword and (it.label == "func" or it.label == "type"))
    end, items)
  end
  if require("utils.goimpl").method_position(ctx.line, ctx.cursor[2]) then
    return {} -- the names come from goimpl (what's missing from the interface), not gopls
  end
  if require("utils.goiferr").fresh(ctx) then
    return {} -- new line after `x, err := …`: only the `if err != nil` block
  end
  if literal_info(ctx) then -- the fields already come from gosmart (with default values)
    return vim.tbl_filter(function(it)
      return it.kind ~= KIND.Field
    end, items)
  end
  local value = value_info(ctx)
  if value then -- the struct already comes filled in from gosmart: without gopls' stray name
    local mine = names_of(value.structs)
    return vim.tbl_filter(function(it)
      return not mine[it.label]
    end, items)
  end
  return items
end

-- ── automatic menu when opening a new line inside `T{ }` ───────────────────────
--- Enter inside `Envelope{` creates a blank line: the menu opens by itself there,
--- without having to type a letter. It repeats after each `field: value,`.
function M.autotrigger()
  vim.api.nvim_create_autocmd("TextChangedI", {
    group = vim.api.nvim_create_augroup("GoSmartLiteral", { clear = true }),
    callback = function(args)
      if vim.bo[args.buf].filetype ~= "go" then
        return
      end
      local line = vim.api.nvim_get_current_line()
      local row, col = unpack(vim.api.nvim_win_get_cursor(0))
      local prev = row > 1 and vim.api.nvim_buf_get_lines(0, row - 2, row - 1, false)[1] or ""
      -- `func (s *noteService) ` just typed: opens the menu with the missing methods (without having to type a letter)
      local impl = require("utils.goimpl").method_position(line, col)
      local inline = line:sub(1, col):match "{$" ~= nil and line:sub(col + 1):match "^}" ~= nil
      -- `Envelope{|}`, or a blank line just opened after `{` or after `field: value,`
      local fresh = line:match "^%s*$" ~= nil and prev:match "[{,]%s*$" ~= nil
      -- `func ` just typed at column 0: if there is something to offer from the already-written code (missing methods, enum
      -- helpers, mappers, handlers), open the menu
      if line == "func " and col == 5 then
        local range = { start = { line = row - 1, character = 0 }, ["end"] = { line = row - 1, character = col } }
        if #M.extra_declaration_items(range, "") > 0 then
          impl = true
        end
      end
      -- new line after `x, err := …`: opens the menu with the `if err != nil` already built
      if not impl and not line:match "%S" and require("utils.goiferr").fresh { line = line, cursor = { row, col } } then
        impl = true
      end
      if impl and (line:sub(1, col):match "%)%s$" or not line:match "%S" or line == "func ") then
        return vim.defer_fn(function()
          local ok, cmp = pcall(require, "blink.cmp")
          local now = vim.api.nvim_win_get_cursor(0)
          if ok and vim.api.nvim_get_mode().mode == "i" and now[1] == row and now[2] == col and not cmp.is_visible() then
            cmp.show()
          end
        end, 40)
      end
      if not (inline or fresh) then
        return
      end
      -- with a short delay: if you just accepted an item, blink is still closing its menu
      vim.defer_fn(function()
        local ok, cmp = pcall(require, "blink.cmp")
        local now = vim.api.nvim_win_get_cursor(0)
        if ok and vim.api.nvim_get_mode().mode == "i" and now[1] == row and now[2] == col and not cmp.is_visible() then
          if literal_info { line = vim.api.nvim_get_current_line(), cursor = { row, col } } then
            cmp.show()
          end
        end
      end, 40)
    end,
  })
end

-- ── blink.cmp source ─────────────────────────────────────────────────────────
local Source = {}
Source.__index = Source

function M.new()
  return setmetatable({}, Source)
end

function Source:enabled()
  return vim.bo.filetype == "go"
end

function Source:resolve(item, callback)
  M.resolve(item, callback)
end

function Source:get_completions(ctx, callback)
  local incomplete = false
  local before = ctx.line:sub(1, ctx.cursor[2])
  local items = type_body_items(before)
  -- `func (s *noteService) |`: the methods missing to satisfy its interface
  if #items == 0 and require("utils.goimpl").method_position(ctx.line, ctx.cursor[2]) then
    -- what's missing from an interface (goimpl) and a service's handlers (gohttp)
    local method_items = require("utils.goimpl").method_items(ctx)
    vim.list_extend(method_items, require("utils.gohttp").method_items(ctx))
    -- the getters of the struct's private fields (gogetters)
    vim.list_extend(method_items, require("utils.gogetters").method_items(ctx))
    return callback { is_incomplete_forward = false, is_incomplete_backward = false, items = method_items }
  end
  local lit = #items == 0 and literal_info(ctx)
  local value = #items == 0 and not lit and value_info(ctx)
  if lit then
    items = literal_items(ctx, lit)
  elseif value then
    items = struct_literal_items(ctx, value)
  elseif #items == 0 then
    local mode, frag = decl_start(ctx)
    if mode then
      items = declaration_items(ctx, mode, frag)
      -- `funcnew` only exists with ≥ 5 letters: blink must ask again while the word grows
      -- (same for the helpers of TYPED_HELPERS: `recon`, `gette`, `repo`)
      incomplete = mode == "any"
        and (
          (#frag < FUNCNEW_MIN and starts("funcnew", frag))
          or vim.iter(TYPED_HELPERS):any(function(name)
            return require("utils." .. name).pending(frag)
          end)
        )
    elseif M.scope(ctx.cursor[1], ctx.cursor[2], ctx.line) == "interface" then
      items = interface_items(ctx)
      -- the methods the related struct already has (goport) go first
      for i, item in ipairs(require("utils.goport").interface_items(ctx)) do
        table.insert(items, i, item)
      end
    elseif M.scope(ctx.cursor[1], ctx.cursor[2], ctx.line) == "func" then
      -- `if err != nil` with the function's returns (goiferr) and already-wired constructors (gowire)
      items = require("utils.goiferr").items(ctx)
      vim.list_extend(items, require("utils.gowire").items(ctx))
    end
  end
  callback { is_incomplete_forward = incomplete, is_incomplete_backward = false, items = items }
end

return M
