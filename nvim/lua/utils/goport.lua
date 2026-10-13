-- ── Go: la interfaz que ya implementa un struct, y su comprobación `var _` (sin LLM, 0 tokens) ─
-- Es el camino inverso de goimpl (que completa los métodos de un struct desde su interfaz):
--   type NoteService interface { | }   → ofrece los métodos exportados de `noteService` que la interfaz aún no tiene,
--                                        con su firma, y "todos" a la vez
--   var _ |  (columna 0)               → `var _ NoteService = (*noteService)(nil)` para los structs del archivo cuya
--                                        interfaz se reconoce (constructor o nombre) y aún no la tienen. Esa línea es
--                                        lo que hace que el compilador avise si falta un método, y que goimpl la reconozca.
local ix = require "utils.goindex"

local M = {}

local KIND = vim.lsp.protocol.CompletionItemKind
local FORMAT = vim.lsp.protocol.InsertTextFormat

--- Nombre de la interfaz que contiene la posición, si es un `type X interface { … }`
---@param row integer
---@param col integer
---@return string?
local function enclosing_interface(row, col)
  local node = ix.node_at(row, col)
  while node do
    if node:type() == "type_spec" then
      local ty = node:field("type")[1]
      local name = node:field("name")[1]
      if ty and name and ty:type() == "interface_type" then
        return vim.treesitter.get_node_text(name, 0)
      end
      return nil
    end
    node = node:parent()
  end
end

--- Métodos exportados de `struct` (de todo el paquete)
---@param pkg GoImplPackage
---@param struct string
---@return GoImplMethod[]
local function exported_methods(pkg, struct)
  local out, seen = {}, {}
  for _, m in ipairs(pkg.methods) do
    if m.recv == struct and m.name:match "^%u" and m.sig and not seen[m.name] then
      seen[m.name] = true
      out[#out + 1] = m
    end
  end
  return out
end

--- Ítems dentro de `type X interface { | }`: lo que implementa el struct relacionado y la interfaz aún no declara
---@param ctx { line: string, cursor: integer[] }
---@return table[]
function M.interface_items(ctx)
  local row, col = ctx.cursor[1], ctx.cursor[2]
  local iface = enclosing_interface(row, col)
  if not iface then
    return {}
  end
  local pkg = ix.current_package()
  if not pkg then
    return {}
  end
  local declared = {}
  for _, m in ipairs(pkg.interfaces[iface] or {}) do
    declared[m.name] = true
  end
  local indent = ctx.line:match "^%s*"
  local frag = ctx.line:sub(1, col):match "([%w_]*)$"
  local range = {
    start = { line = row - 1, character = col - #frag },
    ["end"] = { line = row - 1, character = col },
  }
  local items = {}
  for struct in pairs(pkg.structs) do
    if ix.related(struct, iface) and struct ~= iface then
      local missing = vim.tbl_filter(function(m)
        return not declared[m.name]
      end, exported_methods(pkg, struct))
      if #missing > 0 then
        if #missing > 1 then
          items[#items + 1] = {
            label = ("…all of %s (%d)"):format(struct, #missing),
            labelDetails = { description = "from methods" },
            kind = KIND.Method,
            insertTextFormat = FORMAT.PlainText,
            filterText = "all " .. struct,
            sortText = "000",
            textEdit = {
              newText = table.concat(
                vim.tbl_map(function(m)
                  return m.name .. m.sig
                end, missing),
                "\n" .. indent
              ),
              range = range,
            },
          }
        end
        for _, m in ipairs(missing) do
          items[#items + 1] = {
            label = m.name,
            labelDetails = { description = struct .. " · method" },
            kind = KIND.Method,
            insertTextFormat = FORMAT.PlainText,
            filterText = m.name,
            sortText = ("%03d"):format(#items + 1),
            documentation = { kind = "markdown", value = ("```go\n%s%s\n```"):format(m.name, m.sig) },
            textEdit = { newText = m.name .. m.sig, range = range },
          }
        end
      end
    end
  end
  return vim.tbl_filter(function(it)
    return frag == "" or it.filterText:lower():sub(1, #frag) == frag:lower()
  end, items)
end

--- Ítems al empezar una declaración: la comprobación `var _ I = (*T)(nil)` de los structs del archivo que no la tienen
---@param range table
---@param frag string
---@return table[]
function M.declaration_items(range, frag)
  local pkg, path = ix.current_package()
  if not pkg then
    return {}
  end
  local _, src = ix.buffer_state()
  local has = {}
  for _, a in ipairs(pkg.asserts) do
    has[a.typ .. ">" .. a.iface] = true
  end
  local items = {}
  local structs = vim.tbl_keys(pkg.structs)
  table.sort(structs)
  for _, struct in ipairs(structs) do
    if src:find("type%s+" .. struct .. "%s+struct") then
      for _, iface in ipairs(require("utils.goimpl").candidates(pkg, struct, path)) do
        if not has[struct .. ">" .. iface] then
          local text = ("var _ %s = (*%s)(nil)"):format(iface, struct)
          items[#items + 1] = {
            label = text,
            labelDetails = { description = "compile-time check" },
            kind = KIND.Snippet,
            insertTextFormat = FORMAT.PlainText,
            filterText = ("var assert check %s %s"):format(iface, struct),
            sortText = ("%03d"):format(#items + 1),
            textEdit = { newText = text, range = range },
          }
        end
      end
    end
  end
  return vim.tbl_filter(function(it)
    return frag == "" or ("var"):find(frag:lower(), 1, true) == 1 or it.filterText:lower():find(frag:lower(), 1, true)
  end, items)
end

return M
