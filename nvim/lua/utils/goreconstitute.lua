-- ── Go: `Reconstitute` for a struct, from its fields (no LLM, 0 tokens) ──────
-- The constructor of a persistence layer: it takes EVERY field and sets it, with no validation and no `now`, because the data was
-- valid when it was saved. Optional like `funcnew`: it shows up when starting a declaration and typing `recon…` or
-- `funcrecon…` (5 letters at least), once per struct declared in the file that does not have one yet.
--
--   // Reconstitute rehydrates a Note from persistence without validating it.
--   func Reconstitute(id, title, content string, createdAt, updatedAt time.Time) *Note {
--       return &Note{
--           id:        id,
--           ...
--       }
--   }
--
-- With one struct in the file it is `Reconstitute`; with several, `ReconstituteX`. `gomodel` (`toDomain`) looks for exactly this name.
local ix = require "utils.goindex"

local M = {}

local KIND = vim.lsp.protocol.CompletionItemKind
local FORMAT = vim.lsp.protocol.InsertTextFormat

local MIN = 5 -- typed letters for it to show up
M.MIN = MIN

---@param word string
---@param frag string
---@return boolean
local function starts(word, frag)
  return word:sub(1, #frag):lower() == frag:lower()
end

--- The function for a struct. Contiguous parameters of the same type are grouped (`id, title string`)
---@param name string
---@param fields { name: string, type: string }[]
---@param single boolean only struct in the file → `Reconstitute`
---@param param_name fun(field: string): string
---@return string
function M.text(name, fields, single, param_name)
  local groups, width = {}, 0
  for _, f in ipairs(fields) do
    width = math.max(width, #f.name)
    local p = param_name(f.name)
    local g = groups[#groups]
    if g and g.type == f.type then
      g.names[#g.names + 1] = p
    else
      groups[#groups + 1] = { names = { p }, type = f.type }
    end
  end
  local params, assigns = {}, {}
  for i, g in ipairs(groups) do
    params[i] = ("%s %s"):format(table.concat(g.names, ", "), g.type)
  end
  for _, f in ipairs(fields) do
    assigns[#assigns + 1] = ("\t\t%s:%s %s,"):format(f.name, (" "):rep(width - #f.name), param_name(f.name))
  end
  local fn = single and "Reconstitute" or "Reconstitute" .. name
  local body = #assigns == 0 and ("\treturn &%s{}"):format(name)
    or ("\treturn &%s{\n%s\n\t}"):format(name, table.concat(assigns, "\n"))
  return ("// %s rehydrates a %s from persistence without validating it.\nfunc %s(%s) *%s {\n%s\n}"):format(
    fn,
    name,
    fn,
    table.concat(params, ", "),
    name,
    body
  )
end

--- Is `frag` on its way to showing the item (blink must ask again while the word grows)
---@param frag string
---@return boolean
function M.pending(frag)
  return #frag < MIN and (starts("funcreconstitute", frag) or starts("reconstitute", frag))
end

---@param range table
---@param frag string
---@return table[]
function M.declaration_items(range, frag)
  if #frag < MIN or not (starts("funcreconstitute", frag) or starts("reconstitute", frag)) then
    return {}
  end
  local pkg = ix.current_package()
  if not pkg then
    return {}
  end
  local _, src = ix.buffer_state()
  local names = vim.tbl_filter(function(name)
    return pkg.structs[name] ~= nil -- (the package index has the buffer's text, so these are its current fields)
  end, ix.file_structs())
  local param_name = require("utils.gosmart").param_name
  local items = {}
  for _, name in ipairs(names) do
    local single = #names == 1
    local fn = single and "Reconstitute" or "Reconstitute" .. name
    if not src:find("func%s+" .. fn .. "%s*%(") then
      items[#items + 1] = {
        label = fn,
        labelDetails = { description = ("rehydrate %s"):format(name) },
        kind = KIND.Function,
        insertTextFormat = FORMAT.PlainText,
        filterText = ("funcreconstitute reconstitute %s"):format(name),
        sortText = ("%03d"):format(#items + 1),
        textEdit = { newText = M.text(name, pkg.structs[name], single, param_name), range = range },
      }
    end
  end
  return items
end

return M
