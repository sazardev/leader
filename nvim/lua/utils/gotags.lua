-- ── Go struct tags: blink.cmp source ──────────────────────────────────────────
-- On a field (`Kind Kind `) it derives the tag value from the field's NAME:
--   `            → json:"kind", json:"kind,omitempty", yaml:"kind", db:"kind"...
--   json:        → "kind"  "kind,omitempty"  "kind$0"
--   json:"       → kind  kind,omitempty  camelCase  -
--   json:"kind,  → omitempty  omitzero  string   (depending on the key)
--   gorm:"       → variants depending on the field and its TYPE (`primaryKey;type:text`, `not null`...)
--   gorm:"x;     → standalone options separated by `;` (index, size:255, column:...)
-- The cursor stays inside the quotes so you can type `,` (or Tab to leave).
local M = {}

local KEYS = { "json", "gorm", "yaml", "db", "mapstructure", "form", "toml", "xml" }

local OPTIONS = {
  json = { "omitempty", "omitzero", "string" },
  yaml = { "omitempty", "flow", "inline" },
  mapstructure = { "omitempty", "squash" },
  xml = { "omitempty", "attr", "chardata" },
}
local DEFAULT_OPTIONS = { "omitempty" }

-- gorm separates its options with `;` (not `,`) and some carry a value (`size:255`).
-- { inserted text (with ${n:default}), } — the label is the text with the defaults
local GORM_OPTIONS = {
  "not null",
  "index",
  "uniqueIndex",
  "unique",
  "type:${1:text}",
  "size:${1:255}",
  "column:${1:%s}", -- %s = field name in snake_case
  "default:${1:value}",
  "primaryKey",
  "autoIncrement",
  "autoCreateTime",
  "autoUpdateTime",
  "precision:${1:10}",
  "scale:${1:2}",
  "foreignKey:${1:ID}",
  "references:${1:ID}",
  "many2many:${1:table}",
  "polymorphic:${1:Owner}",
  "embedded",
  "embeddedPrefix:${1:prefix_}",
  "comment:${1:text}",
  "check:${1:expr}",
  "serializer:json",
  "<-:create",
  "<-:update",
  "<-:false",
  "->:false",
  "-",
}

-- First token of a line that is NOT a field (discards stray raw strings)
local NOT_A_FIELD = {}
for _, kw in ipairs { "var", "const", "type", "func", "return", "case", "go", "defer", "if", "else", "for", "switch", "select", "import", "package" } do
  NOT_A_FIELD[kw] = true
end

local STRUCT_NODES = { field_declaration = true, field_declaration_list = true, struct_type = true, ERROR = true }

local SNIPPET = vim.lsp.protocol.InsertTextFormat.Snippet
local KIND = vim.lsp.protocol.CompletionItemKind

---@param name string
---@return string
function M.snake(name)
  local s = name:gsub("(%l)(%u)", "%1_%2"):gsub("(%u+)(%u%l)", "%1_%2")
  return s:lower()
end

---@param name string
---@return string
function M.camel(name)
  local out = {}
  for i, word in ipairs(vim.split(M.snake(name), "_", { plain = true })) do
    out[i] = i == 1 and word or word:sub(1, 1):upper() .. word:sub(2)
  end
  return table.concat(out)
end

--- Is the cursor inside a struct? It only vetoes when treesitter sees something
--- that clearly isn't one (e.g. a raw string of an SQL query).
---@param row integer 1-indexed
---@param col integer 0-indexed
---@return boolean
local function in_struct(row, col)
  local ok, node = pcall(function()
    vim.treesitter.get_parser(0, "go"):parse()
    return vim.treesitter.get_node { pos = { row - 1, math.max(col - 1, 0) } }
  end)
  if not ok or not node then
    return true
  end
  while node do
    if STRUCT_NODES[node:type()] then
      return true
    end
    node = node:parent()
  end
  return false
end

---@class GoTagContext
---@field mode "key"|"value"|"option"
---@field field string field name
---@field key? string tag key (json, yaml...)
---@field tag string tag text up to the cursor
---@field bare? boolean `json:` without quotes yet
---@field type string Go type of the field
---@field value string value of the open tag up to the cursor (gorm only)
---@field row integer
---@field col integer

---@param line string
---@param row integer
---@param col integer 0-indexed, byte
---@return GoTagContext?
function M.context(line, row, col)
  local before = line:sub(1, col)
  local field, rest = before:match "^%s*([%a_][%w_]*)%s+(.*)$"
  if not field or NOT_A_FIELD[field] then
    return nil
  end
  local typ, tag = rest:match "^([^`]-)%s*`([^`]*)$"
  if not typ or typ == "" or typ:find "^[:=,(.]" then
    return nil
  end

  ---@type GoTagContext?
  local ctx
  local open_key, open_value = tag:match '([%w_]+):"([^"]*)$'
  if open_key == "gorm" then
    -- gorm: options separated by `;` that can contain spaces, `:` and `,`
    ctx = { mode = open_value:find(";", 1, true) and "option" or "value", key = "gorm", value = open_value }
  else
    local key = tag:match '([%w_]+):"[^"]*,[%w_,]*$'
    if key then
      ctx = { mode = "option", key = key }
    else
      key = tag:match '([%w_]+):"[%w_%-%.]*$'
      if key then
        ctx = { mode = "value", key = key }
      else
        key = tag:match "([%w_]+):$"
        if key then
          ctx = { mode = "value", key = key, bare = true, value = "" }
        elseif tag:match "^[%w_]*$" or tag:match '"%s+[%w_]*$' then
          ctx = { mode = "key" }
        end
      end
    end
  end
  if not ctx or not in_struct(row, col) then
    return nil
  end
  ctx.field, ctx.tag, ctx.type, ctx.row, ctx.col = field, tag, typ, row, col
  return ctx
end

-- ── gorm ─────────────────────────────────────────────────────────────────────
---@param typ string Go type of the field (`string`, `*time.Time`, `[]byte`...)
---@return "string"|"int"|"float"|"bool"|"time"|"deleted"|"bytes"|"other"
local function kind_of(typ)
  local t = typ:gsub("^%*", "")
  if t == "string" then
    return "string"
  elseif t == "bool" then
    return "bool"
  elseif t:match "^u?int%d*$" then
    return "int"
  elseif t:match "^float%d+$" then
    return "float"
  elseif t == "time.Time" then
    return "time"
  elseif t == "gorm.DeletedAt" then
    return "deleted"
  elseif t == "[]byte" then
    return "bytes"
  end
  return "other"
end

--- Most likely full `gorm:"…"` tag values for the field (by name and type)
---@param field string
---@param typ string
---@return string[]
function M.gorm_variants(field, typ)
  local kind, list, seen = kind_of(typ), {}, {}
  local nullable = typ:sub(1, 1) == "*"
  local function add(v)
    if not seen[v] and not (nullable and v:find("not null", 1, true)) then
      seen[v] = true
      list[#list + 1] = v
    end
  end

  if field == "ID" or field == "Id" then
    if kind == "string" then
      add "primaryKey;type:text"
      add "primaryKey"
      add "primaryKey;type:uuid"
    elseif kind == "int" then
      add "primaryKey;autoIncrement"
      add "primaryKey"
    else
      add "primaryKey"
    end
  elseif kind == "time" then
    if field == "CreatedAt" then
      add "autoCreateTime"
      add "not null;autoCreateTime"
    elseif field == "UpdatedAt" then
      add "autoUpdateTime"
      add "not null;autoUpdateTime"
    end
    add "not null"
    add "index"
  elseif kind == "deleted" then
    add "index"
  elseif kind == "string" then
    add "type:text;not null"
    add "type:text"
    add "not null"
    add "type:text;not null;index"
    add "uniqueIndex"
    add "index"
    add "size:255"
  elseif kind == "bool" then
    add "not null;default:false"
    add "default:false"
    add "index"
  elseif kind == "int" or kind == "float" then
    add "not null"
    add "not null;default:0"
    add "default:0"
    add "index"
  elseif kind == "bytes" then
    add "type:blob"
    add "type:bytea"
  else
    -- relation or custom type (e.g. `Author User`)
    add("foreignKey:" .. field .. "ID")
    add "embedded"
    add("many2many:" .. M.snake(field))
  end
  if kind ~= "other" then
    add("column:" .. M.snake(field))
  end
  add "-"
  return list
end

---@param text string
---@return string
local function snippet_escape(text)
  return (text:gsub("[%$}\\]", "\\%0"))
end

---@param ctx GoTagContext
---@param after string
---@return table[]
local function gorm_items(ctx, after)
  local items = {}
  local row, col = ctx.row, ctx.col
  local function edit(start_col, text)
    return {
      newText = text,
      range = {
        start = { line = row - 1, character = start_col },
        ["end"] = { line = row - 1, character = col },
      },
    }
  end

  if ctx.mode == "value" then
    -- first fragment: full values; the cursor is already after `gorm:"` (or `gorm:`)
    local closed = after:sub(1, 1) == '"'
    for _, v in ipairs(M.gorm_variants(ctx.field, ctx.type or "")) do
      local text = ctx.bare and ('"%s"'):format(v) or (closed and v or v .. '"')
      items[#items + 1] = {
        label = v,
        labelDetails = { description = "gorm" },
        kind = KIND.Value,
        filterText = v,
        sortText = ("%02d"):format(#items + 1),
        insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
        textEdit = edit(col - #ctx.value, text),
      }
    end
    return items
  end

  -- mode == "option": after a `;`, standalone options not yet in the tag
  local used = {}
  local fragments = vim.split(ctx.value, ";", { plain = true })
  for i = 1, #fragments - 1 do
    used[vim.trim(fragments[i]):match "^[^:]*"] = true
  end
  local frag = fragments[#fragments]
  local snake = M.snake(ctx.field)
  for _, opt in ipairs(GORM_OPTIONS) do
    local text = opt:find("%s", 1, true) and opt:format(snake) or opt
    local label = text:gsub("%${%d+:([^}]*)}", "%1")
    if not used[label:match "^[^:]*"] then
      items[#items + 1] = {
        label = label,
        labelDetails = { description = "gorm option" },
        kind = KIND.Property,
        filterText = label,
        sortText = ("%02d"):format(#items + 1),
        insertTextFormat = text:find("%$") and SNIPPET or vim.lsp.protocol.InsertTextFormat.PlainText,
        textEdit = edit(col - #frag, text),
      }
    end
  end
  return items
end

---@param label string
---@param text string
---@param order integer
---@param extra? table
local function item(label, text, order, extra)
  return vim.tbl_extend("force", {
    label = label,
    insertText = text,
    insertTextFormat = SNIPPET,
    kind = KIND.Property,
    sortText = ("%02d"):format(order),
  }, extra or {})
end

-- snake_case and camelCase of the field (without duplicates if they match: Kind → kind)
---@param field string
---@return string[]
local function names(field)
  local snake, camel = M.snake(field), M.camel(field)
  return snake == camel and { snake } or { snake, camel }
end

---@param ctx GoTagContext
---@param after string text after the cursor
---@return table[]
function M.items(ctx, after)
  if ctx.key == "gorm" and ctx.mode ~= "key" then
    return gorm_items(ctx, after)
  end
  local items = {}

  if ctx.mode == "key" then
    local used = {}
    for k in ctx.tag:gmatch '([%w_]+):"' do
      used[k] = true
    end
    -- the closing backtick usually already exists (mini.pairs); if not, it is added
    local close = after:find("`", 1, true) and "" or "`"
    local function add(key, value, snippet_value)
      local label = ('%s:"%s"'):format(key, value)
      items[#items + 1] = item(label, ('%s:"%s"$0'):format(key, snippet_value or value) .. close, #items + 1, { filterText = key })
    end
    local snake, camel = unpack(names(ctx.field))
    for _, key in ipairs(KEYS) do
      if key == "gorm" then
        -- variants by the field's name and type (see M.gorm_variants)
        if not used.gorm then
          for _, v in ipairs(M.gorm_variants(ctx.field, ctx.type)) do
            add("gorm", v, snippet_escape(v))
          end
        end
      elseif not used[key] then
        add(key, snake)
        if key == "json" or key == "yaml" then
          add(key, snake .. ",omitempty")
        end
        if camel and key == "json" then
          add(key, camel)
        end
      end
    end
    if not used.json then
      add("json", "-")
    end
    if not used.validate then
      add("validate", "required", "required$1")
    end
    return items
  end

  if ctx.mode == "option" then
    local done = {}
    local value = ctx.tag:match '"([^"]*)$' or ""
    local fragments = vim.split(value, ",", { plain = true })
    for i = 2, #fragments - 1 do
      done[fragments[i]] = true
    end
    for _, opt in ipairs(OPTIONS[ctx.key] or DEFAULT_OPTIONS) do
      if not done[opt] then
        items[#items + 1] = item(opt, opt, #items + 1, { insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText })
      end
    end
    return items
  end

  -- mode == "value"
  local closed = after:sub(1, 1) == '"'
  local function add(value)
    local text = value
    if ctx.bare then
      text = ('"%s$1"$0'):format(value) -- Tab leaves the quotes
    elseif not closed then
      text = value .. '$1"$0'
    end
    local label = ctx.bare and ('"%s"'):format(value) or value
    items[#items + 1] = item(label, text, #items + 1, {
      filterText = value,
      insertTextFormat = (ctx.bare or not closed) and SNIPPET or vim.lsp.protocol.InsertTextFormat.PlainText,
      kind = KIND.Value,
    })
  end
  for _, name in ipairs(names(ctx.field)) do
    add(name)
    add(name .. ",omitempty")
  end
  add "-"
  return items
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

function Source:get_trigger_characters()
  return { "`", ":", '"', ",", ";" }
end

function Source:resolve(item, callback)
  require("utils.gosmart").resolve(item, callback)
end

function Source:get_completions(ctx, callback)
  local row, col = ctx.cursor[1], ctx.cursor[2]
  local tag = M.context(ctx.line, row, col)
  callback {
    is_incomplete_forward = false,
    is_incomplete_backward = false,
    items = tag and M.items(tag, ctx.line:sub(col + 1)) or {},
  }
end

--- For `completion.list.selection.preselect`: inside a tag the first
--- item is selected and Enter accepts it without going through Tab.
---@return boolean
function M.active()
  if vim.bo.filetype ~= "go" then
    return false
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  return M.context(vim.api.nvim_get_current_line(), row, col) ~= nil
end

return M
