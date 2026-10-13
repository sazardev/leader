-- ── Ámbitos de código con treesitter ─────────────────────────────────────────
-- Usa las queries `textobjects` (@function.outer, @class.outer) de
-- nvim-treesitter-textobjects: la misma definición de "función/clase" que ya usas con
-- `af`/`ac`, para todos los lenguajes que tengan parser. Sin query, no hay ámbito
-- (el llamador cae a un párrafo de líneas).
local M = {}

local loaded = false

--- Las queries viven en un plugin con carga perezosa: se carga la primera vez que hace falta
local function ensure_plugin()
  if loaded then
    return
  end
  loaded = true
  local ok, lazy = pcall(require, "lazy")
  if ok then
    pcall(lazy.load, { plugins = { "nvim-treesitter-textobjects" } })
  end
end

---@param buf integer
---@return TSNode?, string?, vim.treesitter.Query?
function M.parse(buf)
  ensure_plugin()
  local ok, parser = pcall(vim.treesitter.get_parser, buf, nil, { error = false })
  if not ok or not parser then
    return nil
  end
  local trees = parser:parse()
  local root = trees and trees[1] and trees[1]:root()
  if not root then
    return nil
  end
  local lang = parser:lang()
  local qok, query = pcall(vim.treesitter.query.get, lang, "textobjects")
  return root, lang, qok and query or nil
end

--- Filas (0-based, inclusivas) que ocupa un nodo
---@param node TSNode
---@return integer, integer
local function rows(node)
  local sr, _, er, ec = node:range()
  if ec == 0 and er > sr then
    er = er - 1
  end
  return sr, er
end

-- Nodos que son DEFINICIONES de tipo aunque la query `class.outer` de ese lenguaje no las capture
-- (p. ej. interface y enum en Java).
local TYPE_NODE = {
  "struct",
  "class",
  "interface",
  "enum",
  "trait",
  "type_alias",
  "type_declaration",
  "record",
  "protocol",
  "object_declaration",
}

---@param node_type string
---@return boolean
local function type_like(node_type)
  for _, p in ipairs(TYPE_NODE) do
    if node_type:find(p, 1, true) then
      return true
    end
  end
  return false
end

--- Nombre declarado por un nodo: su campo `name` (en el propio nodo o un poco más abajo: Go lo pone en
--- `type_spec`, TypeScript bajo `export_statement`) o, en un `impl` de Rust, su campo `type`
---@param node TSNode
---@param src integer|string buffer o texto
---@return string?
local function declared_name(node, src)
  -- un `impl` se llama como el tipo que implementa; su `name` más cercano sería el de un método suyo
  if node:type():find("impl", 1, true) then
    local ty = node:field("type")[1]
    if ty then
      return vim.treesitter.get_node_text(ty, src)
    end
  end
  local function find(n, depth)
    local field = n:field("name")[1]
    if field then
      return vim.treesitter.get_node_text(field, src)
    end
    if depth > 0 then
      for child in n:iter_children() do
        if child:named() then
          local found = find(child, depth - 1)
          if found then
            return found
          end
        end
      end
    end
  end
  local name = find(node, 3)
  if name then
    return name
  end
  local ty = node:field("type")[1]
  return ty and vim.treesitter.get_node_text(ty, src) or nil
end

---@param node TSNode
---@param buf integer
---@return string?
local function name_of(node, buf)
  return declared_name(node, buf)
end

--- Sube el inicio para incluir los comentarios contiguos de encima (la doc es la especificación)
---@param buf integer
---@param root TSNode
---@param first integer 1-based
---@return integer
local function include_leading_comments(buf, root, first)
  local row = first - 2
  while row >= 0 do
    local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
    local col = line:find "%S"
    if not col then
      break
    end
    local node = root:named_descendant_for_range(row, col - 1, row, col - 1)
    if not (node and node:type():find "comment") then
      break
    end
    first = row + 1
    row = row - 1
  end
  return first
end

---@class AgentScope
---@field first integer 1-based
---@field last integer 1-based inclusive
---@field name string?

--- El ámbito más interno ("function" | "class") que contiene la fila
---@param buf integer
---@param row integer 0-based
---@param scope string
---@return AgentScope?
function M.enclosing(buf, row, scope)
  local root, _, query = M.parse(buf)
  if not (root and query) then
    return nil
  end
  local wanted = scope .. ".outer"
  local best
  for id, node in query:iter_captures(root, buf, row, row + 1) do
    if query.captures[id] == wanted then
      local sr, er = rows(node)
      if sr <= row and row <= er and (not best or (er - sr) < (best.last - best.first)) then
        best = { first = sr + 1, last = er + 1, node = node }
      end
    end
  end
  if not best then
    return nil
  end
  return {
    first = include_leading_comments(buf, root, best.first),
    last = best.last,
    name = name_of(best.node, buf),
  }
end

---@class AgentTypeDecl
---@field name string?
---@field kind string  tipo del nodo ("type_declaration", "class_declaration", "impl_item"...)
---@field first integer 1-based
---@field last integer 1-based, inclusivo

--- Definiciones de tipo (struct, clase, interfaz, enum, trait, alias...) de un buffer o de un texto
---@param src integer|string buffer, o el texto de un archivo
---@param lang string? obligatorio con texto
---@return AgentTypeDecl[]
function M.type_declarations(src, lang)
  local root, query
  if type(src) == "number" then
    root, _, query = M.parse(src)
  else
    ensure_plugin()
    local ok, parser = pcall(vim.treesitter.get_string_parser, src, lang)
    if not ok then
      return {}
    end
    root = parser:parse()[1]:root()
    local qok, q = pcall(vim.treesitter.query.get, lang, "textobjects")
    query = qok and q or nil
  end
  if not root then
    return {}
  end

  local list, seen = {}, {}
  local function add(node)
    -- `class.outer` también captura cosas que NO son definiciones (en Go, los literales `&Order{...}`)
    local t = node:type()
    if not (type_like(t) or t:find("impl", 1, true)) then
      return
    end
    local sr, er = rows(node)
    local name = declared_name(node, src)
    local key = (name or "") .. ":" .. sr
    if not seen[key] then
      seen[key] = true
      list[#list + 1] = { name = name, kind = node:type(), first = sr + 1, last = er + 1 }
    end
  end

  if query then
    for id, node in query:iter_captures(root, src, 0, -1) do
      if query.captures[id] == "class.outer" then
        add(node)
      end
    end
  end
  -- lo que la query no captura: hijos del archivo (y un nivel más, por `export ...`) con pinta de tipo
  for child in root:iter_children() do
    if type_like(child:type()) then
      add(child)
    elseif child:named() then
      for grandchild in child:iter_children() do
        if grandchild:named() and type_like(grandchild:type()) then
          add(grandchild)
        end
      end
    end
  end
  table.sort(list, function(a, b)
    return a.first < b.first
  end)
  return list
end

--- Nombres de tipo que usa un nodo (`*type_identifier*` y, donde no los hay, identificadores en PascalCase)
---@param name string
---@return boolean
function M.pascal_case(name)
  return name:match "^[A-Z]" ~= nil and name:match "%l" ~= nil
end

---@param node TSNode
---@param src integer
---@return { name: string, row: integer, col: integer }[]
function M.type_names(node, src, first, last)
  local found, seen = {}, {}
  local function walk(n)
    local row, col = n:start()
    if row + 1 >= first and row + 1 <= last then
      local t = n:type()
      local is_type = t:find "type_identifier" ~= nil
      local is_pascal = (t == "identifier" or t:find "identifier$") ~= nil and not is_type
      if is_type or is_pascal then
        local name = vim.treesitter.get_node_text(n, src)
        if not seen[name] and (is_type or M.pascal_case(name)) then
          seen[name] = true
          found[#found + 1] = { name = name, row = row, col = col }
        end
      end
    end
    for child in n:iter_children() do
      walk(child)
    end
  end
  walk(node)
  return found
end

local ACCESS = { "selector", "member", "field_expression", "attribute", "access", "dot_index", "navigation" }

---@param t string
---@return boolean
local function is_access(t)
  for _, p in ipairs(ACCESS) do
    if t:find(p, 1, true) then
      return true
    end
  end
  return false
end

--- El identificador del OBJETO de un acceso (`x.Titl` -> x; `a.b.c` -> b), si el nodo es la parte derecha de uno:
--- un diagnóstico sobre el miembro (`no field Titl`) se explica con el tipo del objeto, no con el del miembro.
---@param n TSNode
---@param src integer
---@return { name: string, row: integer, col: integer }?
local function operand_of(n, src)
  local parent = n:parent()
  if not (parent and is_access(parent:type())) then
    return nil
  end
  local first = parent:named_child(0)
  if not first or first:id() == n:id() then
    return nil
  end
  while first and is_access(first:type()) and first:named_child_count() > 0 do
    first = first:named_child(first:named_child_count() - 1)
  end
  if first and first:type():find "identifier" and first:named_child_count() == 0 then
    local row, col = first:start()
    return { name = vim.treesitter.get_node_text(first, src), row = row, col = col }
  end
  return nil
end

--- Identificadores dentro de un rango (0-based; `ecol` exclusivo), y el objeto de cada acceso (`x.Titl` -> también x).
--- Con rango vacío, el que hay en ese punto. Sirve para preguntar al LSP por los objetos a los que apunta un diagnóstico.
---@param buf integer
---@param srow integer
---@param scol integer
---@param erow integer
---@param ecol integer
---@return { name: string, row: integer, col: integer }[]
function M.identifiers_in(buf, srow, scol, erow, ecol)
  local root = M.parse(buf)
  if not root then
    return {}
  end
  if erow == srow and ecol <= scol then
    ecol = scol + 1
  end
  local out, seen = {}, {}
  local function add(id)
    local key = id.row .. ":" .. id.col
    if not seen[key] then
      seen[key] = true
      out[#out + 1] = id
    end
  end
  local function walk(n)
    local nsr, nsc, ner, nec = n:range()
    if ner < srow or (ner == srow and nec <= scol) or nsr > erow or (nsr == erow and nsc >= ecol) then
      return
    end
    if n:type():find "identifier" and n:named_child_count() == 0 then
      -- primero el objeto (es lo que explica el diagnóstico), luego el propio identificador
      local operand = operand_of(n, buf)
      if operand then
        add(operand)
      end
      add { name = vim.treesitter.get_node_text(n, buf), row = nsr, col = nsc }
    end
    for child in n:iter_children() do
      walk(child)
    end
  end
  local node = root:named_descendant_for_range(srow, scol, erow, ecol)
  if node then
    walk(node)
  end
  return out
end

--- Bloques de constantes de primer nivel que mencionan el tipo (el "enum" de Go: `const ( Pending Status = ... )`)
---@param src integer|string buffer o texto
---@param lang string? obligatorio con texto
---@param name string nombre del tipo
---@return { first: integer, last: integer }[]
function M.constants_of(src, lang, name)
  local root
  if type(src) == "number" then
    root = M.parse(src)
  else
    local ok, parser = pcall(vim.treesitter.get_string_parser, src, lang)
    root = ok and parser:parse()[1]:root() or nil
  end
  local out = {}
  if not root then
    return out
  end
  for child in root:iter_children() do
    if child:named() and child:type():find "^const" then
      local text = vim.treesitter.get_node_text(child, src)
      if text:find("%f[%w_]" .. name .. "%f[^%w_]") then
        local sr, er = rows(child)
        out[#out + 1] = { first = sr + 1, last = er + 1 }
      end
    end
  end
  return out
end

---@class AgentFunction
---@field name string?
---@field first integer 1-based
---@field last integer 1-based, inclusivo

--- Funciones y métodos de un buffer o de un texto (con su nombre y rango)
---@param src integer|string buffer, o el texto de un archivo
---@param lang string? obligatorio con texto
---@return AgentFunction[]
function M.functions(src, lang)
  local root, query
  if type(src) == "number" then
    root, _, query = M.parse(src)
  else
    ensure_plugin()
    local ok, parser = pcall(vim.treesitter.get_string_parser, src, lang)
    if not ok then
      return {}
    end
    root = parser:parse()[1]:root()
    local qok, q = pcall(vim.treesitter.query.get, lang, "textobjects")
    query = qok and q or nil
  end
  local list = {}
  if not (root and query) then
    return list
  end
  for id, node in query:iter_captures(root, src, 0, -1) do
    if query.captures[id] == "function.outer" then
      local sr, er = rows(node)
      list[#list + 1] = { name = declared_name(node, src), first = sr + 1, last = er + 1 }
    end
  end
  table.sort(list, function(a, b)
    return a.first < b.first
  end)
  return list
end

--- Todas las declaraciones (funciones y clases) del archivo, en orden
---@param buf integer
---@return { row: integer, last: integer, kind: "function"|"class" }[]
function M.declarations(buf)
  local root, _, query = M.parse(buf)
  if not (root and query) then
    return {}
  end
  local list = {}
  for id, node in query:iter_captures(root, buf, 0, -1) do
    local name = query.captures[id]
    if name == "function.outer" or name == "class.outer" then
      local sr, er = rows(node)
      list[#list + 1] = { row = sr, last = er, kind = name == "class.outer" and "class" or "function" }
    end
  end
  table.sort(list, function(a, b)
    return a.row < b.row
  end)
  return list
end

return M
