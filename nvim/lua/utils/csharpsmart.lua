-- ── Context-aware C# (.NET) completion ───────────────────────────────────────
-- A blink.cmp source (`cs` only). It reads the treesitter tree to know WHERE
-- the cursor is and the project index (utils/csharpindex.lua) to offer what
-- Roslyn cannot know about THIS project:
--   start of a declaration  → class / record / interface / struct named after the file
--   inside a class          → ctor (from its fields), props (get-only accessors),
--                             DbSet<Entity> for a DbContext, override/implement templates
--   inside a method or a top-level Program.cs
--                           → services.AddScoped<INoteService, NoteService>() for every
--                             service/interface pair of the project
-- Items that need a type from another namespace carry their `using`; Source:execute
-- inserts it after the snippet (the same trick dartheader uses).
local index = require "utils.csharpindex"

local M = {}

local KIND = vim.lsp.protocol.CompletionItemKind
local FORMAT = vim.lsp.protocol.InsertTextFormat

local TYPE_PREFIX = {
  class = "class",
  record = "record",
  interface = "interface",
  struct = "struct",
  enum = "enum",
}

local LIFETIMES = { "AddScoped", "AddSingleton", "AddTransient" }

--- Is `word` a prefix of `target` with at least `min` letters typed?
---@param word string
---@param target string
---@param min integer?
---@return boolean
local function starts(word, target, min)
  return #word >= (min or 1) and vim.startswith(target, word)
end

local SYSTEM_INTERFACES = {
  IDisposable = true,
  IAsyncDisposable = true,
  IEquatable = true,
  IComparable = true,
  ICloneable = true,
  IServiceProvider = true,
}

---@return table
local function settings()
  return require("core.settings").csharp or {}
end

---@param path string
---@return string
function M.type_name(path)
  local base = vim.fs.basename(path):gsub("%.cs$", "")
  return (base:gsub("[-_](%w)", string.upper):gsub("^%l", string.upper))
end

---@param name string
---@return string
function M.interface_name(name)
  return name:match "^I%u" and name or ("I" .. name)
end

---@param name string
---@return string
function M.plural(name)
  if name:match "[^aeiou]y$" then
    return name:sub(1, -2) .. "ies"
  end
  if name:match "[sxz]$" or name:match "ch$" or name:match "sh$" then
    return name .. "es"
  end
  return name .. "s"
end

---@param node TSNode
---@param buf integer
---@param row integer
---@param col integer
---@return TSNode?
local function node_at(buf, row, col)
  local ok, node = pcall(function()
    local parser = vim.treesitter.get_parser(buf, "c_sharp")
    local root = parser:parse()[1]:root()
    local r, c = row - 1, math.max(col - 1, 0)
    return root:named_descendant_for_range(r, c, r, c)
  end)
  return ok and node or nil
end

local last_context = { key = "", value = nil }

--- Where the cursor is: top, inside a type, inside a method, or elsewhere
---@param buf integer
---@param row integer
---@param col integer
---@param line string
---@return { scope: "top"|"class"|"method"|"other", class: CSharpType?, node: TSNode? }
function M.context(buf, row, col, line)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  local key = ("%d:%d:%d:%d"):format(buf, vim.b[buf].changedtick or 0, row, col)
  if last_context.key == key then
    return last_context.value
  end
  local value = { scope = "other" }
  local node = node_at(buf, row, col)
  local type_node, in_type_body, in_block = nil, false, false
  while node do
    local t = node:type()
    if t == "block" or t == "arrow_expression_clause" then
      in_block = true
    elseif t == "method_declaration" or t == "constructor_declaration" or t == "local_function_statement" then
      if in_block then
        value.scope = "method"
      end
      break
    elseif t == "declaration_list" then
      local parent = node:parent()
      if
        parent
        and (
          parent:type() == "class_declaration"
          or parent:type() == "record_declaration"
          or parent:type() == "struct_declaration"
        )
      then
        in_type_body = true
      end
    elseif t == "class_declaration" or t == "record_declaration" or t == "struct_declaration" then
      type_node = node
      break
    elseif t == "compilation_unit" then
      value.scope = "top"
      break
    end
    node = node:parent()
  end
  if value.scope ~= "method" then
    if type_node then
      -- the header of the type (typing `cla` at the top) is a declaration position; its body is the class
      value.scope = in_type_body and "class" or "top"
    elseif line:find "^%s*[%w_]*$" then
      value.scope = "top"
    end
  end
  value.node = type_node
  if type_node then
    local info = index.scan_buffer(buf)
    value.class = index.type_at(info, row)
    value.namespace = info.namespace
  end
  last_context = { key = key, value = value }
  return value
end

--- The word typed at the start of the line (after indentation) and the indentation
---@param ctx blink.cmp.Context
---@return string word, string indent
function M.decl_word(ctx)
  local before = ctx.line:sub(1, ctx.cursor[2])
  local indent, word = before:match "^(%s*)([%w_]*)$"
  return word or "", indent or ""
end

---@param ctx blink.cmp.Context
---@param word string
---@return table
local function range_of(ctx, word)
  return {
    start = { line = ctx.cursor[1] - 1, character = math.max(ctx.cursor[2] - #word, 0) },
    ["end"] = { line = ctx.cursor[1] - 1, character = ctx.cursor[2] },
  }
end

---@param label string
---@param detail string
---@param kind integer
---@param text string
---@param range table
---@param opts table?
---@return table
local function item(label, detail, kind, text, range, opts)
  opts = opts or {}
  return {
    label = label,
    labelDetails = { description = detail },
    kind = kind,
    insertTextFormat = FORMAT.Snippet,
    textEdit = { newText = text, range = range },
    filterText = opts.filter or label,
    sortText = opts.sort or label,
    data = { usings = opts.usings or {} },
  }
end

-- ── declarations named after the file ─────────────────────────────────────────

---@param path string
---@param word string
---@param indent string?
---@return table[]
function M.declaration_items(path, word, indent)
  if #word < 2 then
    return {}
  end
  indent = indent or ""
  local base = M.type_name(path)
  if base == "" then
    return {}
  end
  local lower = word:lower()
  local range = nil -- filled by the caller
  local out = {}
  local function add(kind, name, text, detail)
    if not vim.startswith(kind, lower) and not vim.startswith(text:match "^[%w_]+" or "", lower) then
      return
    end
    out[#out + 1] = { kind = kind, name = name, text = text, detail = detail }
  end
  local function body(kind, name)
    return ("%s %s\n%s{\n%s\t$0\n%s}"):format(kind, name, indent, indent, indent)
  end
  add("class", base, body("class", base), "named after the file")
  add("record", base, body("record", base), "named after the file")
  add("interface", M.interface_name(base), body("interface", M.interface_name(base)), "named after the file")
  add("struct", base, body("struct", base), "named after the file")
  add("enum", base, body("enum", base), "named after the file")
  for _, d in ipairs(out) do
    d.range = range
  end
  return out
end

-- ── constructor / properties / DbSet ─────────────────────────────────────────

--- The fields a generated constructor would take
---@param type CSharpType
---@return { name: string, field: CSharpMember, type: string }[]
function M.constructor_fields(type)
  local out = {}
  for _, f in ipairs(type.fields or {}) do
    local private = f.name:match "^_" ~= nil or vim.tbl_contains(f.modifiers or {}, "private")
    if
      private
      and not f.static
      and not f.initialized
      and f.type
      and not vim.tbl_contains(f.modifiers or {}, "const")
    then
      local name = f.name:gsub("^_+", "")
      if name == "" then
        name = f.name
      end
      out[#out + 1] = { name = name, field = f, type = f.type }
    end
  end
  return out
end

---@param type CSharpType
---@param indent string
---@return string?
function M.constructor_text(type, indent)
  if #(type.primary or {}) > 0 then
    return nil
  end
  local fields = M.constructor_fields(type)
  if #fields == 0 then
    return nil
  end
  local params, assigns = {}, {}
  for i, f in ipairs(fields) do
    params[i] = ("%s %s"):format(f.type, f.name)
    assigns[i] = ("%s\t%s = %s;"):format(indent, f.field.name, f.name)
  end
  return ("public %s(%s)\n%s{\n%s\n%s}"):format(
    type.name,
    table.concat(params, ", "),
    indent,
    table.concat(assigns, "\n"),
    indent
  )
end

---@param type CSharpType
---@param indent string
---@return { label: string, text: string }[]
function M.property_items(type, indent)
  local existing = {}
  for _, p in ipairs(type.properties or {}) do
    existing[p.name] = true
  end
  local out = {}
  for _, f in ipairs(type.fields or {}) do
    local private = f.name:match "^_" ~= nil or vim.tbl_contains(f.modifiers or {}, "private")
    if private and not f.static and f.type and not vim.tbl_contains(f.modifiers or {}, "const") then
      local name = M.type_name(f.name:gsub("^_+", ""))
      if name ~= "" and not existing[name] then
        existing[name] = true
        out[#out + 1] = { label = name, text = ("public %s %s => %s;"):format(f.type, name, f.name) }
      end
    end
  end
  return out
end

---@param type CSharpType
---@return boolean
function M.is_db_context(type)
  if type.kind ~= "class" then
    return false
  end
  if type.name:match "DbContext$" then
    return true
  end
  for _, base in ipairs(type.base_names or {}) do
    if base == "DbContext" then
      return true
    end
  end
  return false
end

---@param project CSharpProject
---@param current CSharpType?
---@param namespace string?
---@return table[]
function M.dbset_items(project, current, namespace)
  local out = {}
  local present = {}
  if current then
    for _, p in ipairs(current.properties or {}) do
      present[p.name] = true
    end
    for _, f in ipairs(current.fields or {}) do
      present[f.name] = true
    end
  end
  for _, entity in ipairs(project.entities or {}) do
    if entity ~= current and not present[M.plural(entity.name)] then
      local plural = M.plural(entity.name)
      present[plural] = true
      local usings = entity.namespace and entity.namespace ~= namespace and { entity.namespace } or {}
      out[#out + 1] = {
        label = ("DbSet<%s> %s"):format(entity.name, plural),
        detail = entity.namespace or "entity",
        text = ("public DbSet<%s> %s => Set<%s>();"):format(entity.name, plural, entity.name),
        usings = usings,
      }
    end
  end
  return out
end

--- The interface that names a service (`INoteService` for `NoteService`), else its first own interface
---@param service CSharpType
---@return string?
function M.service_interface(service)
  local names = service.interfaces or {}
  local own = M.interface_name(service.name)
  for _, name in ipairs(names) do
    if name == own then
      return name
    end
  end
  for _, name in ipairs(names) do
    if not SYSTEM_INTERFACES[name] then
      return name
    end
  end
end

--- DI registrations for the project's services
---@param project CSharpProject
---@param typed string what follows the dot (`A`, `Add`, `AddS`…)
---@param namespace string?
---@return table[]
function M.di_items(project, typed, namespace)
  local lifetimes = {}
  for _, life in ipairs(LIFETIMES) do
    if vim.startswith(life, typed) then
      lifetimes[#lifetimes + 1] = life
    end
  end
  if #lifetimes == 0 then
    return {}
  end
  local out = {}
  for _, service in ipairs(project.services or {}) do
    if #out >= 90 then
      break
    end
    local iface = M.service_interface(service)
    local usings = {}
    for _, ns in ipairs {
      service.namespace,
      iface and project.by_name[iface] and project.by_name[iface].namespace or nil,
    } do
      if ns and ns ~= namespace and not vim.tbl_contains(usings, ns) then
        usings[#usings + 1] = ns
      end
    end
    for _, life in ipairs(lifetimes) do
      local generic = iface and ("<%s, %s>"):format(iface, service.name) or ("<%s>"):format(service.name)
      out[#out + 1] = {
        label = life .. generic,
        detail = ("%s · %s"):format(life:gsub("^Add", ""):lower(), service.namespace or "this project"),
        text = life .. generic .. "()",
        usings = usings,
        filter = life .. " " .. (iface or "") .. " " .. service.name,
      }
    end
  end
  return out
end

-- ── usings ────────────────────────────────────────────────────────────────────

---@param buf integer
---@param list string[]
---@param namespace string?
---@return string[]
function M.missing_usings(buf, list, namespace)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local present = {}
  for _, line in ipairs(lines) do
    local name = line:match "^%s*using%s+static%s+([%w_%.]+)"
      or line:match "^%s*global%s+using%s+static%s+([%w_%.]+)"
      or (not line:find("=", 1, true) and line:match "^%s*using%s+([%w_%.]+)%s*;")
      or (not line:find("=", 1, true) and line:match "^%s*global%s+using%s+([%w_%.]+)%s*;")
    if name then
      present[name] = true
    end
  end
  local out, seen = {}, {}
  for _, name in ipairs(list or {}) do
    if name and name ~= "" and name ~= namespace and not present[name] and not seen[name] then
      seen[name] = true
      out[#out + 1] = name
    end
  end
  return out
end

---@param buf integer
---@param list string[]
---@param namespace string?
function M.apply_usings(buf, list, namespace)
  local missing = M.missing_usings(buf, list, namespace)
  if #missing == 0 then
    return
  end
  table.sort(missing)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local row = 0
  for i, line in ipairs(lines) do
    if line:match "^%s*using%s+[%w_%.]+%s*;" or line:match "^%s*global%s+using%s+[%w_%.]+%s*;" then
      row = i
    end
  end
  local insert = {}
  for _, name in ipairs(missing) do
    insert[#insert + 1] = "using " .. name .. ";"
  end
  vim.api.nvim_buf_set_lines(buf, row, row, false, insert)
end

-- ── preview / source ─────────────────────────────────────────────────────────

---@param item table
---@return string
local function preview_text(item)
  local text = item.textEdit and item.textEdit.newText or item.insertText or item.label
  if item.insertTextFormat == FORMAT.Snippet then
    local ok, parsed = pcall(vim.lsp._snippet_grammar.parse, text)
    if ok and parsed then
      return tostring(parsed)
    end
  end
  return text
end

---@param item table
---@param callback fun(item: table)
function M.resolve(item, callback)
  local resolved = vim.deepcopy(item)
  local text = preview_text(item)
  resolved.documentation = { kind = "markdown", value = "```csharp\n" .. text .. "\n```" }
  callback(resolved)
end

local Source = {}
Source.__index = Source

function M.new()
  return setmetatable({}, Source)
end

function Source:enabled()
  return vim.bo.filetype == "cs"
end

function Source:resolve(item, callback)
  M.resolve(item, callback)
end

function Source:execute(ctx, item, callback, default_implementation)
  default_implementation()
  local cfg = settings()
  if cfg.smart and cfg.smart.usings ~= false then
    local info = index.scan_buffer(ctx.bufnr)
    M.apply_usings(ctx.bufnr, item.data and item.data.usings or {}, info.namespace)
  end
  callback()
end

---@param ctx blink.cmp.Context
---@param callback fun(response: table)
function Source:get_completions(ctx, callback)
  local cfg = settings()
  if not cfg.smart or cfg.smart.enabled == false then
    return callback { is_incomplete_forward = false, is_incomplete_backward = false, items = {} }
  end
  local buf = ctx.bufnr
  local row, col = ctx.cursor[1], ctx.cursor[2]
  local word, indent = M.decl_word(ctx)
  local lower = word:lower()
  local context = M.context(buf, row, col, ctx.line)
  local path = vim.api.nvim_buf_get_name(buf)
  local range = range_of(ctx, word)
  local items = {}
  local incomplete = false

  local function add(list)
    for _, it in ipairs(list) do
      items[#items + 1] = item(it.label, it.detail, it.kind or KIND.Text, it.text, it.range or range, {
        usings = it.usings,
        filter = it.filter,
        sort = it.sort,
      })
    end
  end

  if context.scope == "top" then
    if cfg.smart.declarations ~= false then
      local decls = M.declaration_items(path, word, indent)
      for _, d in ipairs(decls) do
        d.label = d.kind .. " " .. d.name
        d.kind = d.kind == "class" and KIND.Class
          or d.kind == "interface" and KIND.Interface
          or d.kind == "enum" and KIND.Enum
          or KIND.Struct
        d.range = range
      end
      add(decls)
    end
  end

  if context.scope == "class" and context.class then
    if cfg.smart.constructor ~= false and starts(lower, "ctor", 2) then
      local text = M.constructor_text(context.class, indent)
      if text then
        local label = text:match "^public%s+[^(]+%((.-)%)" or "ctor"
        add {
          {
            label = "ctor(" .. label .. ")",
            detail = ("constructor from %d fields"):format(#M.constructor_fields(context.class)),
            kind = KIND.Constructor,
            text = text,
            filter = "ctor constructor " .. context.class.name,
            sort = "01",
          },
        }
      end
      incomplete = lower ~= "ctor"
    elseif cfg.smart.properties ~= false and starts(lower, "props", 3) then
      local props = M.property_items(context.class, indent)
      if #props > 0 then
        local lines = {}
        for i, p in ipairs(props) do
          -- the first line starts where the typed word was (the line's indentation stays); the rest carry it
          lines[i] = (i == 1 and "" or indent) .. p.text
        end
        add {
          {
            label = ("props (%d)"):format(#props),
            detail = "get-only properties from private fields",
            kind = KIND.Property,
            text = table.concat(lines, "\n"),
            filter = "props properties " .. context.class.name,
            sort = "01",
          },
        }
      end
      incomplete = lower ~= "props"
    elseif cfg.smart.dbset ~= false and starts(lower, "dbset", 2) then
      if M.is_db_context(context.class) then
        local root = require("utils.csharpproj").root(vim.fs.dirname(path))
        local info = index.scan_buffer(buf)
        local project =
          index.project(root, { path = path, text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") })
        add(M.dbset_items(project, context.class, info.namespace))
      end
      incomplete = lower ~= "dbset"
    elseif starts(lower, "override", 4) then
      add {
        {
          label = "override",
          detail = "method template",
          kind = KIND.Method,
          text = "public override ${1:void} ${2:Name}(${3})\n{\n\t$0\n}",
          sort = "01",
        },
      }
    elseif starts(lower, "implement", 4) then
      add {
        {
          label = "implement",
          detail = "interface member template",
          kind = KIND.Method,
          text = "public ${1:void} ${2:Name}(${3})\n{\n\tthrow new NotImplementedException();\n}",
          sort = "01",
        },
      }
    end
  end

  if context.scope ~= "class" then
    local _, typed = ctx.line:sub(1, col):match "^(.*)%.(A[%w]*)$"
    if
      cfg.smart.di ~= false
      and typed
      and (typed == "A" or vim.iter(LIFETIMES):any(function(life)
        return vim.startswith(life, typed)
      end))
    then
      local root = require("utils.csharpproj").root(vim.fs.dirname(path))
      local info = index.scan_buffer(buf)
      local project =
        index.project(root, { path = path, text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") })
      local di = M.di_items(project, typed, info.namespace)
      for _, d in ipairs(di) do
        d.kind = KIND.Function
        d.range = range_of(ctx, typed)
        d.sort = "00" .. d.label
      end
      add(di)
      incomplete = typed ~= "AddScoped" and typed ~= "AddSingleton" and typed ~= "AddTransient"
    end
  end

  callback { is_incomplete_forward = incomplete, is_incomplete_backward = false, items = items }
end

return M
