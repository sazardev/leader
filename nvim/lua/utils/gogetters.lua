-- ── Go: getters for the private fields of a struct (no LLM, 0 tokens) ────────
-- An aggregate keeps its state private and exposes it through accessors, with no `Get` prefix and no setters (changes go through
-- methods that mean something). For every unexported field of a struct declared in the current file that has no accessor yet:
--
--   func (n *Note) ID() string           { return n.id }
--   func (n *Note) Title() string        { return n.title }
--   func (n *Note) CreatedAt() time.Time { return n.createdAt }
--   func (n *Note) Tags() []string       { return slices.Clone(n.tags) }
--
-- Two ways in:
--   · at package level, typing `getters` (or `funcgetters`, `accessors`; 5 letters at least): all the missing ones at once, per struct
--   · after `func (n *Note) ` (the menu opens by itself): one item per missing getter, plus "all the getters"
-- The receiver is the one your other methods use (else the struct's first letter, pointer). Names follow Go's initialisms
-- (`id` → `ID`, `userId` → `UserID`, `url` → `URL`). A slice or map comes back as a copy (`settings.go.getters.clone`), so the caller
-- cannot change the aggregate through it; a pointer field is returned as it is.
local ix = require "utils.goindex"

local M = {}

local KIND = vim.lsp.protocol.CompletionItemKind
local FORMAT = vim.lsp.protocol.InsertTextFormat

local MIN = 5 -- typed letters for the declaration item to show up
local WORDS = { "funcgetters", "getters", "accessors" }

--- Words Go writes in capitals
local INITIALISMS = {
  id = true,
  url = true,
  uri = true,
  uuid = true,
  api = true,
  http = true,
  https = true,
  ip = true,
  sql = true,
  json = true,
  xml = true,
  html = true,
  css = true,
  ttl = true,
  utc = true,
  tls = true,
  ssh = true,
  cpu = true,
  ascii = true,
}

---@param word string
---@param frag string
---@return boolean
local function starts(word, frag)
  return word:sub(1, #frag):lower() == frag:lower()
end

---@param frag string
---@return boolean
local function wants(frag)
  return vim.iter(WORDS):any(function(w)
    return starts(w, frag)
  end)
end

--- Is `frag` on its way to showing the declaration item (blink must ask again while the word grows)
---@param frag string
---@return boolean
function M.pending(frag)
  return #frag < MIN and wants(frag)
end

--- `createdAt` → `CreatedAt`, `id` → `ID`, `userId` → `UserID`, `httpClient` → `HTTPClient`
---@param field string
---@return string
function M.method_name(field)
  local out = {}
  for _, word in ipairs(vim.split(field:gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2"), " ", { plain = true })) do
    out[#out + 1] = INITIALISMS[word:lower()] and word:upper() or (word:sub(1, 1):upper() .. word:sub(2))
  end
  return table.concat(out)
end

--- What a getter returns: the field, or a copy of it when it is a slice or a map
---@param recv string
---@param field { name: string, type: string }
---@param clone boolean
---@return string expression
local function value(recv, field, clone)
  local access = recv .. "." .. field.name
  if clone and field.type:match "^%[%]" then
    return ("slices.Clone(%s)"):format(access)
  elseif clone and field.type:match "^map%[" then
    return ("maps.Clone(%s)"):format(access)
  end
  return access
end

---@class GoGetter
---@field name string     `ID`
---@field type string
---@field field string    `id`
---@field expr string     what it returns, with the receiver in it

--- The getters a struct is missing
---@param pkg GoImplPackage
---@param struct string
---@param recv string receiver variable
---@param clone boolean
---@return GoGetter[]
function M.missing(pkg, struct, recv, clone)
  local have = {}
  for _, m in ipairs(pkg.methods) do
    if m.recv == struct then
      have[m.name] = true
    end
  end
  local out = {}
  for _, f in ipairs(pkg.structs[struct] or {}) do
    local name = M.method_name(f.name)
    -- an exported field is already reachable; `_` is padding; a method with that name (or the field's own name) is taken
    if f.name:match "^[%l_]" and f.name ~= "_" and not have[name] and name ~= f.name then
      out[#out + 1] = { name = name, type = f.type, field = f.name, expr = value(recv, f, clone) }
    end
  end
  return out
end

--- The receiver the struct's other methods use, else its first letter. Pointer unless every method takes a value
---@param pkg GoImplPackage
---@param struct string
---@return string var, boolean ptr
function M.receiver(pkg, struct)
  local var, ptrs, values = nil, 0, 0
  for _, m in ipairs(pkg.methods) do
    if m.recv == struct then
      var = var or (m.var ~= "" and m.var ~= "_" and m.var or nil)
      if m.ptr then
        ptrs = ptrs + 1
      else
        values = values + 1
      end
    end
  end
  return var or struct:sub(1, 1):lower(), not (values > 0 and ptrs == 0)
end

--- The getters as gofmt writes them: one line each, the bodies aligned
---@param struct string
---@param getters GoGetter[]
---@param recv string
---@param ptr boolean
---@return string
function M.text(struct, getters, recv, ptr)
  local heads, width = {}, 0
  for i, g in ipairs(getters) do
    heads[i] = ("func (%s %s%s) %s() %s"):format(recv, ptr and "*" or "", struct, g.name, g.type)
    width = math.max(width, #heads[i])
  end
  local lines = {}
  for i, g in ipairs(getters) do
    lines[i] = ("%s%s { return %s }"):format(heads[i], (" "):rep(width - #heads[i]), g.expr)
  end
  return table.concat(lines, "\n")
end

---@return boolean
local function clone_setting()
  local ok, settings = pcall(require, "core.settings")
  local go = ok and settings.go
  return not (go and go.getters and go.getters.clone == false)
end

--- At package level: `getters` for each struct of the file that is missing some
---@param range table
---@param frag string
---@return table[]
function M.declaration_items(range, frag)
  if #frag < MIN or not wants(frag) then
    return {}
  end
  local pkg = ix.current_package()
  if not pkg then
    return {}
  end
  local names = vim.tbl_filter(function(name)
    return pkg.structs[name] ~= nil
  end, ix.file_structs())
  local items = {}
  for _, struct in ipairs(names) do
    local recv, ptr = M.receiver(pkg, struct)
    local getters = M.missing(pkg, struct, recv, clone_setting())
    if #getters > 0 then
      local single = #names == 1
      items[#items + 1] = {
        label = single and "getters" or "getters " .. struct,
        labelDetails = { description = ("%d for %s"):format(#getters, struct) },
        kind = KIND.Snippet,
        insertTextFormat = FORMAT.PlainText,
        filterText = ("funcgetters getters accessors %s"):format(struct),
        sortText = ("%03d"):format(#items + 1),
        textEdit = { newText = M.text(struct, getters, recv, ptr), range = range },
      }
    end
  end
  return items
end

--- After `func (n *Note) `: what is typed is the method's name, so each item completes it and what follows
---@param ctx { line: string, cursor: integer[] }
---@return table[]
function M.method_items(ctx)
  local struct, frag, from, receiver = require("utils.goimpl").method_position(ctx.line, ctx.cursor[2])
  if not struct then
    return {}
  end
  local pkg = ix.current_package()
  if not pkg or not pkg.structs[struct] then
    return {}
  end
  local recv = receiver.var ~= "" and receiver.var or select(1, M.receiver(pkg, struct))
  local getters = M.missing(pkg, struct, recv, clone_setting())
  if #getters == 0 then
    return {}
  end
  local range = ix.range_of(ctx.cursor[1], from, ctx.cursor[2])
  local items = {}
  for i, g in ipairs(getters) do
    items[#items + 1] = {
      label = g.name,
      labelDetails = { description = ("→ %s · getter"):format(g.type) },
      kind = KIND.Method,
      insertTextFormat = FORMAT.PlainText,
      filterText = g.name,
      sortText = ("!%03d"):format(i),
      textEdit = { newText = ("%s() %s { return %s }"):format(g.name, g.type, g.expr), range = range },
    }
  end
  if #getters > 1 then
    -- the first one continues what is typed; the rest are whole functions below it
    local all = M.text(struct, getters, recv, receiver.ptr)
    items[#items + 1] = {
      label = "all getters",
      labelDetails = { description = ("%d for %s"):format(#getters, struct) },
      kind = KIND.Snippet,
      insertTextFormat = FORMAT.PlainText,
      filterText = "getters all accessors " .. struct,
      sortText = "!999",
      textEdit = { newText = all:gsub("^func%s%b()%s", ""), range = range },
    }
  end
  return vim.tbl_filter(function(it)
    return frag == "" or it.filterText:lower():sub(1, #frag) == frag:lower() or it.label == "all getters"
  end, items)
end

return M
