-- ── Go: cablear constructores (composition root) sin LLM, 0 tokens ───────────
-- En `main` (o donde armas las dependencias), teclear `New…` ofrece los constructores de los paquetes del módulo con
-- los argumentos YA puestos a partir de lo que hay en ámbito:
--   noteRepo := infrastructure.NewNoteRepository(db)
--   noteService := application.NewNoteService(noteRepo)        ← `noteRepo` va solo: su tipo cumple domain.NoteRepository
-- Cómo elige cada argumento (el primero que encaje): una variable del MISMO tipo → una variable cuyo tipo concreto
-- IMPLEMENTA la interfaz que pide el parámetro (por los métodos) → una variable con el mismo NOMBRE que el parámetro →
-- `context.Background()` para un context → un hueco con el nombre del parámetro. Los tipos de las variables salen de los
-- parámetros, de `var x T`, de `&T{}` y del retorno de los constructores que ya llamaste. El import lo añade goimports al guardar.
local ix = require "utils.goindex"

local M = {}

local KIND = vim.lsp.protocol.CompletionItemKind
local FORMAT = vim.lsp.protocol.InsertTextFormat

local FRAG_MIN = 3
local ITEMS_MAX = 8

---@param t string
---@return string
local function strip(t)
  return (t:gsub("[%w_]+%.", ""):gsub("^%*", ""))
end

---@class GoWireCtor
---@field pkg GoImplPackage
---@field name string
---@field params { name: string?, type: string }[]
---@field results string[]

--- Constructores `NewX` del módulo (y del paquete actual), de los paquetes importados primero
---@param path string
---@param current GoImplPackage
---@return GoWireCtor[], table<string, GoWireCtor>, GoImplModule?
local function constructors(path, current)
  local module = ix.module_packages(path)
  local imported = {}
  for _, import_path in pairs(current.imports) do
    imported[import_path] = true
  end
  local list, by_call = {}, {}
  local packages = module and module.packages or {}
  for _, p in ipairs(packages) do
    for _, f in ipairs(p.funcs) do
      if f.name:match "^New%u" and #f.results > 0 then
        local c = { pkg = p, name = f.name, params = f.params, results = f.results, imported = imported[p.import_path] }
        list[#list + 1] = c
        by_call[(p.name or "") .. "." .. f.name] = c
        if p.dir == current.dir then
          by_call[f.name] = c
        end
      end
    end
  end
  table.sort(list, function(a, b)
    if (a.imported or false) ~= (b.imported or false) then
      return a.imported or false
    end
    return a.name < b.name
  end)
  return list, by_call, module
end

---@class GoWireVar
---@field name string
---@field type string?     normalizado (sin paquete ni `*`)
---@field written string?
---@field pkg GoImplPackage? paquete donde se declaró el tipo (para saber sus métodos)

--- Variables de la función que contiene el cursor, leídas del texto desde su `func` hasta la línea actual
---@param row integer
---@param by_call table<string, GoWireCtor>
---@return GoWireVar[]
local function scope_vars(row, by_call)
  local start
  for r = row, 1, -1 do
    local line = vim.api.nvim_buf_get_lines(0, r - 1, r, false)[1] or ""
    if line:match "^func%s" then
      start = r
      break
    end
  end
  if not start then
    return {}
  end
  local lines = vim.api.nvim_buf_get_lines(0, start - 1, row - 1, false)
  local src = table.concat(lines, "\n") .. "\n}"
  local ok, parser = pcall(vim.treesitter.get_string_parser, src, "go")
  if not ok then
    return {}
  end
  local root = parser:parse()[1]:root()
  local vars = {}
  local function add(name, written, pkg)
    if name ~= "_" then
      vars[#vars + 1] = { name = name, written = written, type = written and strip(written) or nil, pkg = pkg }
    end
  end
  local function text(n)
    return vim.treesitter.get_node_text(n, src)
  end

  --- tipo de una expresión de la derecha
  local function infer(expr)
    local t = expr:type()
    if t == "unary_expression" and expr:named_child(0) then
      return infer(expr:named_child(0))
    elseif t == "composite_literal" then
      local ty = expr:field("type")[1]
      return ty and text(ty) or nil
    elseif t == "call_expression" then
      local fn = expr:field("function")[1]
      local c = fn and by_call[text(fn)]
      if c then
        return c.results[1], c.pkg
      end
    end
  end

  local function walk(n)
    local t = n:type()
    if t == "function_declaration" or t == "method_declaration" or t == "func_literal" then
      for _, p in ipairs((ix.flat_params(n:field("parameters")[1], src))) do
        if p.name then
          add(p.name, p.type)
        end
      end
    elseif t == "short_var_declaration" then
      local left, right = n:field("left")[1], n:field("right")[1]
      if left and right then
        local ids = left:named_children()
        local values = right:named_children()
        for i, id in ipairs(ids) do
          local written, pkg
          if #values == #ids then
            written, pkg = infer(values[i])
          elseif #values == 1 then
            written, pkg = infer(values[1]) -- `x, err := NewX(...)`: el primero es el valor
            if i > 1 then
              written, pkg = i == #ids and "error" or nil, nil
            end
          end
          add(text(id), written, pkg)
        end
      end
    elseif t == "var_spec" then
      local ty = n:field("type")[1]
      for _, name in ipairs(n:field "name") do
        add(text(name), ty and text(ty) or nil)
      end
    end
    for child in n:iter_children() do
      walk(child)
    end
  end
  walk(root)
  return vars
end

--- Métodos (nombres) que tiene un tipo concreto, buscándolo en los paquetes del módulo
---@param name string
---@param packages GoImplPackage[]
---@param prefer GoImplPackage?
---@return table<string, boolean>?
local function methods_of(name, packages, prefer)
  local function in_pkg(p)
    if p.structs[name] then
      local set = {}
      for _, m in ipairs(p.methods) do
        if m.recv == name then
          set[m.name] = true
        end
      end
      return set
    end
  end
  return (prefer and in_pkg(prefer))
    or (function()
      for _, p in ipairs(packages) do
        local set = in_pkg(p)
        if set then
          return set
        end
      end
    end)()
end

--- Nombres de los métodos de una interfaz del módulo
---@param name string
---@param packages GoImplPackage[]
---@return string[]?
local function interface_names(name, packages)
  for _, p in ipairs(packages) do
    local methods = p.interfaces[name]
    if methods then
      return vim.tbl_map(function(m)
        return m.name
      end, methods)
    end
  end
end

--- Elige el argumento para un parámetro
---@param param { name: string?, type: string }
---@param vars GoWireVar[]
---@param packages GoImplPackage[]
---@return string? expr
local function pick(param, vars, packages)
  local want = strip(param.type)
  for _, v in ipairs(vars) do
    if v.type == want then
      return v.name
    end
  end
  local iface = interface_names(want, packages)
  if iface then
    for _, v in ipairs(vars) do
      local have = v.type and methods_of(v.type, packages, v.pkg)
      if have then
        local all = true
        for _, name in ipairs(iface) do
          all = all and have[name]
        end
        if all then
          return v.name
        end
      end
    end
  end
  if param.name then
    for _, v in ipairs(vars) do
      if v.name == param.name then
        return v.name
      end
    end
  end
  if param.type == "context.Context" then
    return "context.Background()"
  end
end

--- `NewNoteService` → noteService
---@param name string
---@return string
local function var_name(name)
  local base = name:gsub("^New", "")
  return (
    base
      :gsub("^(%u+)(%u%l)", function(a, b)
        return a:lower() .. b
      end)
      :gsub("^%u", string.lower)
  )
end

---@param ctx { line: string, cursor: integer[] }
---@return string? frag
function M.position(ctx)
  local frag = ctx.line:sub(1, ctx.cursor[2]):match "^%s*([%w_]+)$"
  if frag and #frag >= FRAG_MIN then
    return frag
  end
end

---@param ctx { line: string, cursor: integer[] }
---@return table[]
function M.items(ctx)
  local frag = M.position(ctx)
  if not frag then
    return {}
  end
  local row, col = ctx.cursor[1], ctx.cursor[2]
  -- solo dentro de una función
  local fn_start
  for r = row, 1, -1 do
    if (vim.api.nvim_buf_get_lines(0, r - 1, r, false)[1] or ""):match "^func%s" then
      fn_start = r
      break
    end
  end
  if not fn_start then
    return {}
  end

  local pkg, path = ix.current_package()
  if not pkg then
    return {}
  end
  local list, by_call, module = constructors(path, pkg)
  local packages = module and module.packages or {}
  local vars = scope_vars(row, by_call)
  local indent = #ctx.line:match "^%s*"
  local range = { start = { line = row - 1, character = indent }, ["end"] = { line = row - 1, character = col } }
  local lower = frag:lower()

  local items = {}
  for _, c in ipairs(list) do
    local vname = var_name(c.name)
    local match = c.name:lower():sub(1, #lower) == lower
      or vname:lower():sub(1, #lower) == lower
      or (#lower >= 4 and c.name:lower():find(lower, 1, true) ~= nil)
    if match and #items < ITEMS_MAX then
      local qual = c.pkg.dir == pkg.dir and "" or ((c.pkg.name or vim.fs.basename(c.pkg.dir)) .. ".")
      local args, plain_args, stop = {}, {}, 0
      for _, p in ipairs(c.params) do
        local expr = pick(p, vars, packages)
        if expr then
          args[#args + 1] = ix.esc(expr)
          plain_args[#plain_args + 1] = expr
        else
          stop = stop + 1
          local label = p.name or strip(p.type):lower()
          args[#args + 1] = ("${%d:%s}"):format(stop, ix.esc(label))
          plain_args[#plain_args + 1] = label
        end
      end
      local has_err = c.results[#c.results] == "error" and #c.results > 1
      local lhs = vname .. (has_err and ", err" or "")
      local body = ("%s := %s%s(%s)"):format(lhs, qual, c.name, table.concat(args, ", "))
      local plain = ("%s := %s%s(%s)"):format(lhs, qual, c.name, table.concat(plain_args, ", "))
      items[#items + 1] = {
        label = ("%s := %s%s(…)"):format(vname, qual, c.name),
        labelDetails = { description = c.pkg.name or "" },
        kind = KIND.Function,
        insertTextFormat = FORMAT.Snippet,
        filterText = ("%s %s %s"):format(c.name, vname, qual .. c.name),
        sortText = ("%03d"):format(#items + 1),
        documentation = { kind = "markdown", value = "```go\n" .. plain .. "\n```" },
        textEdit = { newText = body .. (stop == 0 and "$0" or ""), range = range },
      }
    end
  end
  return items
end

return M
