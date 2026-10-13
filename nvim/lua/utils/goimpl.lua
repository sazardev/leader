-- ── Go: what's left to implement of an interface (no LLM, 0 tokens) ──────────
-- If a struct already "looks like" it implements an interface and is missing methods, it offers EXACTLY those, with the
-- interface's signature and a useful body, as a blink completion (consumed by utils/gosmart.lua):
--   func (s *noteService) |        → the missing methods (after typing the receiver), and "all the missing ones"
--   func |  (column 0)             → the same for each struct in the file, with the receiver already written
-- How it knows which interface a struct implements (the first that fits, in this order):
--   1. `var _ NoteService = (*noteService)(nil)`            (the idiomatic check)
--   2. a constructor that returns it: `func NewX(...) NoteService { return &noteService{...} }`
--   3. the name: noteService ~ NoteService, postgresNoteRepository ~ domain.NoteRepository (imported local packages)
--   4. what it already implemented: if its methods are a subset of the interface's
-- Body: if the struct holds a dependency that is an interface (`repo domain.NoteRepository`) and it has a method
-- with the SAME shape (parameter and return types, regardless of package), the body calls it:
-- `return s.repo.FindByID(ctx, id)`. Otherwise it leaves the cursor in the body with a compiling zero-value `return`.
-- Interfaces from ANOTHER package in the module (`domain.NoteRepository`) are read from disk (go.mod's module) and their types
-- are qualified (`Note` → `domain.Note`); missing imports are added by goimports on save.
-- Interfaces from the standard library or dependencies aren't read: for those, use gopls ("Declare missing methods", <leader>ca).
local M = {}

local KIND = vim.lsp.protocol.CompletionItemKind
local FORMAT = vim.lsp.protocol.InsertTextFormat

local ix = require "utils.goindex"
local KEYWORDS = ix.KEYWORDS
local BUILTIN = ix.BUILTIN
local package_at, module_dir = ix.package_at, ix.module_dir
local related, resolve_interface, defined_methods = ix.related, ix.resolve_interface, ix.defined_methods
local normalize, zero_value, esc, range_of = ix.normalize, ix.zero_value, ix.esc, ix.range_of
local buffer_state, current_package = ix.buffer_state, ix.current_package

-- ── which interface a struct implements and what it's missing ────────────────

---@class GoImplTarget
---@field struct string
---@field iface string          name as written (`NoteService`, `domain.NoteRepository`)
---@field methods GoImplMethod[] the MISSING ones
---@field alias string?         interface's package if it is from another package
---@field declared table<string, boolean>? types declared in the interface's package (qualified with `alias`)
---@field recv string           receiver name
---@field ptr boolean

--- Candidate interfaces for the struct, in order of confidence (no duplicates)
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
  -- imported local packages: `postgresNoteRepository` ~ domain.NoteRepository
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
  -- what it already implemented: its methods are a subset of the interface's
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

-- ── body and signature ───────────────────────────────────────────────────────

--- Signature with the interface's types qualified if it comes from another package
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

--- Short parameter name derived from its type (`context.Context` → ctx, `*domain.Note` → note, `UserID` → userID)
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

--- Parameter names (the interface's, or made up and de-duplicated when it has none)
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

--- Signature with names on all parameters (the interface's if it already has them)
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

--- A complete method: `Name(params) results {\n\tbody\n}` (with the `func (r *T) ` header if `header`)
---@param m GoImplMethod
---@param target GoImplTarget
---@param pkg GoImplPackage
---@param deps { field: string, methods: GoImplMethod[] }[]
---@param header boolean
---@param stop string  snippet marker where the cursor ends up: `$0` (a single one) or `$N` (several methods at once)
---@return string snippet, string plain
local function render(m, target, pkg, deps, header, stop)
  local names = param_names(m)
  local sig = named_signature(m, target, names)
  local recv = ("(%s %s%s)"):format(target.recv, target.ptr and "*" or "", target.struct)

  -- does any dependency have a method with the same shape? (same name wins if there are several)
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
    -- a call already made needs no cursor; only with a single method does the cursor end at the end
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

-- ── blink items ───────────────────────────────────────────────────────────────

---@param plain string
---@param iface string
---@return table
local function documentation(plain, iface)
  return { kind = "markdown", value = ("`%s` · missing\n```go\n%s\n```"):format(iface, plain) }
end

--- Items for the methods `struct` is missing
---@param target GoImplTarget[]
---@param pkg GoImplPackage
---@param file_path string
---@param range table
---@param header boolean  the text carries `func (r *T) ` (starting a declaration) or just the name
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
      -- all at once: the first one already goes at the cursor position; the rest, with their full header
      local joined, joined_plain = {}, {}
      for i, m in ipairs(tg.methods) do
        -- several methods: a single `$0` can't be repeated, so each empty body gets its own `$N` (Tab jumps)
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

--- Position `func (s *noteService) Ge|`: the receiver's struct, what was typed of the name and how the receiver was written
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

--- Items when typing a method name (after `func (s *T) `)
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
    -- the receiver is written as you typed it (`s *noteService`): the bodies use that name
    tg.recv, tg.ptr = receiver.var ~= "" and receiver.var or tg.recv, receiver.ptr
  end
  local items = items_for(targets, pkg, path, range_of(ctx.cursor[1], from, ctx.cursor[2]), false, 0)
  return vim.tbl_filter(function(it)
    return frag == "" or it.filterText:lower():sub(1, #frag) == frag:lower()
  end, items)
end

--- Items when STARTING a declaration: for each struct in the file that is missing methods
---@param range table
---@param frag string what was typed after `func ` (or the word, in `any` mode)
---@return table[]
function M.declaration_items(range, frag)
  local pkg, path = current_package()
  if not pkg then
    return {}
  end
  local targets = {}
  local _, src = buffer_state()
  for struct in pairs(pkg.structs) do
    -- only the structs of THIS file: the rest of the package's show up when typing their receiver
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

--- Interfaces attributed to a struct (for `var _ I = (*T)(nil)`), in order of confidence
---@param pkg GoImplPackage
---@param struct string
---@param file_path string
---@return string[]
function M.candidates(pkg, struct, file_path)
  return candidates(pkg, struct, file_path)
end

--- For tests: what a struct is missing, without building items
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
