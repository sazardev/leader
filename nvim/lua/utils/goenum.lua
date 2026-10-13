-- ── Go: helpers for an enum, from its `const` block (no LLM, 0 tokens) ─
-- A Go enum is `type Status string` (or int) + a `const ( StatusPending Status = "pending" ... )`. For each one
-- declared in the file, when starting a declaration (`func ` at column 0) it offers what it doesn't have yet:
--   func (s Status) IsValid() bool            switch over the constants
--   func ParseStatus(v string) (Status, error)  validates and returns, with a readable error
--   func (s *Status) UnmarshalText(...)        JSON/YAML/flags validate on read (uses ParseStatus)
--   func (s Status) String() / MarshalText()   only on numeric enums (iota): lowercase name
-- and an "…enum helpers" item with all of them at once. What's already written isn't offered again.
local ix = require "utils.goindex"

local M = {}

local KIND = vim.lsp.protocol.CompletionItemKind
local FORMAT = vim.lsp.protocol.InsertTextFormat

---@param t string
---@return "string"|"int"|nil
local function enum_kind(t)
  if t == "string" then
    return "string"
  elseif t:match "^u?int%d*$" then
    return "int"
  end
end

--- `StatusPending` → "pending", `InProgress` → "in_progress" (without the type prefix)
---@param const string
---@param type_name string
---@return string
local function value_name(const, type_name)
  local base = const
  if base:sub(1, #type_name) == type_name and base:sub(#type_name + 1, #type_name + 1):match "%u" then
    base = base:sub(#type_name + 1)
  end
  return require("utils.gotags").snake(base)
end

---@class GoEnum
---@field name string
---@field kind "string"|"int"
---@field consts { name: string, lit: string? }[]

--- Enums declared in `src` (buffer text) and with constants in the package
---@param pkg GoImplPackage
---@param src string
---@return GoEnum[]
local function enums_of(pkg, src)
  local out = {}
  for name, underlying in pairs(pkg.types) do
    local kind = enum_kind(underlying)
    if kind and src:find("type%s+" .. name .. "%s") then
      local consts = {}
      for _, c in ipairs(pkg.consts) do
        if c.type == name and c.name ~= "_" then
          consts[#consts + 1] = { name = c.name, lit = c.lit }
        end
      end
      if #consts > 0 then
        out[#out + 1] = { name = name, kind = kind, consts = consts }
      end
    end
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

---@param e GoEnum
---@return string
local function names_list(e)
  return table.concat(
    vim.tbl_map(function(c)
      return c.name
    end, e.consts),
    ", "
  )
end

--- Bodies of an enum's helpers, by item name
---@param e GoEnum
---@param recv string
---@return { key: string, label: string, text: string }[]
local function helpers(e, recv)
  local T = e.name
  local list = {}
  local function add(key, label, text)
    list[#list + 1] = { key = key, label = label, text = text }
  end

  add(
    "IsValid",
    ("func (%s %s) IsValid"):format(recv, T),
    ("func (%s %s) IsValid() bool {\n\tswitch %s {\n\tcase %s:\n\t\treturn true\n\t}\n\treturn false\n}"):format(
      recv,
      T,
      recv,
      names_list(e)
    )
  )

  if e.kind == "string" then
    add(
      "Parse" .. T,
      "func Parse" .. T,
      ('func Parse%s(v string) (%s, error) {\n\tswitch s := %s(v); s {\n\tcase %s:\n\t\treturn s, nil\n\t}\n\treturn "", fmt.Errorf("invalid %s %%q", v)\n}'):format(
        T,
        T,
        T,
        names_list(e),
        require("utils.gotags").snake(T):gsub("_", " ")
      )
    )
  else
    local cases = {}
    for _, c in ipairs(e.consts) do
      cases[#cases + 1] = ("\tcase %q:\n\t\treturn %s, nil"):format(value_name(c.name, T), c.name)
    end
    add(
      "Parse" .. T,
      "func Parse" .. T,
      ('func Parse%s(v string) (%s, error) {\n\tswitch v {\n%s\n\t}\n\treturn 0, fmt.Errorf("invalid %s %%q", v)\n}'):format(
        T,
        T,
        table.concat(cases, "\n"),
        require("utils.gotags").snake(T):gsub("_", " ")
      )
    )
    local names = {}
    for _, c in ipairs(e.consts) do
      names[#names + 1] = ("\tcase %s:\n\t\treturn %q"):format(c.name, value_name(c.name, T))
    end
    add(
      "String",
      ("func (%s %s) String"):format(recv, T),
      ('func (%s %s) String() string {\n\tswitch %s {\n%s\n\t}\n\treturn fmt.Sprintf("%s(%%d)", int(%s))\n}'):format(
        recv,
        T,
        recv,
        table.concat(names, "\n"),
        T,
        recv
      )
    )
    add(
      "MarshalText",
      ("func (%s %s) MarshalText"):format(recv, T),
      ("func (%s %s) MarshalText() ([]byte, error) {\n\treturn []byte(%s.String()), nil\n}"):format(recv, T, recv)
    )
  end

  add(
    "UnmarshalText",
    ("func (%s *%s) UnmarshalText"):format(recv, T),
    ("func (%s *%s) UnmarshalText(text []byte) error {\n\tv, err := Parse%s(string(text))\n\tif err != nil {\n\t\treturn err\n\t}\n\t*%s = v\n\treturn nil\n}"):format(
      recv,
      T,
      T,
      recv
    )
  )
  return list
end

--- Items when STARTING a declaration, for the file's enums
---@param range table
---@param frag string what was typed after `func ` (or the word, in `any` mode)
---@return table[]
function M.declaration_items(range, frag)
  local pkg = ix.current_package()
  if not pkg then
    return {}
  end
  local _, src = ix.buffer_state()
  local items = {}
  for _, e in ipairs(enums_of(pkg, src)) do
    local have_methods = ix.defined_methods(pkg, e.name)
    local have_funcs = {}
    for _, f in ipairs(pkg.funcs) do
      have_funcs[f.name] = true
    end
    local recv = ix.receiver_name(e.name)
    local missing = vim.tbl_filter(function(h)
      return not have_methods[h.key] and not have_funcs[h.key]
    end, helpers(e, recv))
    local function item(label, detail, text, order, filter)
      return {
        label = label,
        labelDetails = { description = detail },
        kind = KIND.Snippet,
        insertTextFormat = FORMAT.Snippet,
        filterText = filter,
        sortText = ("%03d"):format(order),
        documentation = { kind = "markdown", value = "```go\n" .. text .. "\n```" },
        textEdit = { newText = ix.esc(text), range = range },
      }
    end
    if #missing > 1 then
      local all = table.concat(
        vim.tbl_map(function(h)
          return h.text
        end, missing),
        "\n\n"
      )
      items[#items + 1] = item(
        ("func …enum helpers %s (%d)"):format(e.name, #missing),
        "enum",
        all,
        #items + 1,
        ("func enum %s helpers all"):format(e.name)
      )
    end
    for _, h in ipairs(missing) do
      items[#items + 1] =
        item(h.label, e.name .. " · enum", h.text, #items + 1, ("func enum %s %s"):format(e.name, h.key))
    end
  end
  return vim.tbl_filter(function(it)
    return frag == "" or ("func"):find(frag:lower(), 1, true) == 1 or it.filterText:lower():find(frag:lower(), 1, true)
  end, items)
end

--- For tests
---@param type_name string
---@return string[] keys of what is missing
function M.missing(type_name)
  local pkg = ix.current_package()
  if not pkg then
    return {}
  end
  local _, src = ix.buffer_state()
  for _, e in ipairs(enums_of(pkg, src)) do
    if e.name == type_name then
      local have = ix.defined_methods(pkg, e.name)
      local funcs = {}
      for _, f in ipairs(pkg.funcs) do
        funcs[f.name] = true
      end
      return vim.tbl_map(
        function(h)
          return h.key
        end,
        vim.tbl_filter(function(h)
          return not have[h.key] and not funcs[h.key]
        end, helpers(e, "x"))
      )
    end
  end
  return {}
end

return M
