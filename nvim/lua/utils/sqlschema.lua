-- ── Real tables and columns, locally (blink source, `sql` only) ────────────────
-- sqls already completes tables and columns, but it is a separate process that has to connect and cache the schema;
-- DuckDB has no sqls driver at all. The schema queries here are 3–20 ms and come from the same connection, so offer
-- their answer locally and instantly. One process per table names, one per table's columns, cached per project and
-- connection; blink calls back when the answer is ready. No tokens, no resident process.
local M = {}
local KIND = vim.lsp.protocol.CompletionItemKind
local Source = {}
Source.__index = Source

local TTL = 5 * 60 * 1000
---@type table<string, { at: integer, names: string[]?, columns: table<string, string[]>?, pending: fun()[]? }>
local cache = {}

local function sqlrun()
  return require "sqlrun"
end

local function root_of(ctx)
  local name = vim.api.nvim_buf_get_name(ctx.bufnr)
  if name == "" or name:match "^%a[%w+.-]*://" then
    return sqlrun().root()
  end
  return vim.fs.root(vim.fs.dirname(vim.fn.fnamemodify(name, ":p")), { ".git", ".env", "config.yml" })
    or vim.fs.dirname(vim.fn.fnamemodify(name, ":p"))
end

local function key_of(root, c)
  return root .. "\0" .. c.target
end

local function slot(key)
  local s = cache[key]
  if not s or (s.at and vim.uv.now() - s.at > TTL) then
    s = { at = 0, columns = {}, pending = {} }
    cache[key] = s
  end
  return s
end

--- Loads the table names at most once; every caller is called back (queued while the client runs).
---@param root string
---@param c SqlConnection
---@param cb fun(names: string[])
function M.names(root, c, cb)
  local key = key_of(root, c)
  local s = slot(key)
  if s.names then
    return cb(s.names)
  end
  s.pending[#s.pending + 1] = cb
  if #s.pending > 1 then
    return
  end
  require("sqlrun.schema").tables_of(c, root, function(tables)
    s.names = vim.tbl_map(function(t)
      return t.name
    end, tables or {})
    s.at = vim.uv.now()
    local waiting = s.pending
    s.pending = {}
    for _, done in ipairs(waiting) do
      done(s.names)
    end
  end)
end

--- Columns of one table, loaded on demand (a project can have hundreds of tables).
---@param root string
---@param c SqlConnection
---@param table string
---@param cb fun(columns: { name: string, type: string }[])
function M.columns(root, c, table, cb)
  local key = key_of(root, c)
  local s = slot(key)
  if s.columns[table] then
    return cb(s.columns[table])
  end
  local call_key = "columns:" .. table
  if s[call_key] then
    s[call_key][#s[call_key] + 1] = cb
    return
  end
  s[call_key] = { cb }
  require("sqlrun.schema").columns_of(c, root, { schema = "", name = table }, function(columns)
    s.columns[table] = columns or {}
    local waiting = s[call_key]
    s[call_key] = nil
    for _, done in ipairs(waiting) do
      done(s.columns[table])
    end
  end)
end

--- Forgets what was read (a connection change, a migration, ...).
function M.invalidate()
  cache = {}
end

--- What the text before the cursor asks for: "tables" after FROM/JOIN/..., the alias after `o.`, else "columns"/nil.
---@param before string
---@return { kind: "tables"|"columns"|"alias", alias: string? }?
function M.context(before)
  local word = before:match "[%w_]*$" or ""
  local head = (before:sub(1, #before - #word)):gsub("%s+$", "")
  local tail = (head:match "[%w_]+$" or ""):lower()
  if tail == "" then
    tail = word:lower()
  end
  if tail:match "^from$" or tail:match "^join$" or tail:match "^into$" or tail:match "^update$"
    or tail:match "^table$" or tail:match "^describe$" then
    return { kind = "tables" }
  end
  local dotted = head:match "([%w_]+)%.$"
  if dotted then
    return { kind = "alias", alias = dotted:lower() }
  end
  if tail:match "^where$" or tail:match "^and$" or tail:match "^or$" or tail:match "^select$"
    or tail:match "^by$" or tail:match "^set$" or tail:match "^on$" or tail:match "^having$"
    or tail:match "^using$" then
    return { kind = "columns" }
  end
end

local STOP = {}
for _, word in ipairs {
  "where", "join", "left", "right", "inner", "full", "outer", "cross", "natural", "on", "using", "group", "order",
  "having", "limit", "offset", "union", "set", "values", "returning", "and", "or", "with", "select", "insert",
  "update", "delete", "into", "as", "fetch", "window", "qualify",
} do
  STOP[word] = true
end

--- The table an alias points at, from `from orders o` / `join products p` in the buffer. An empty alias takes the
--- first table mentioned, for a bare `WHERE` / `SELECT` with no `alias.` in front.
---@param lines string[]
---@param alias string
---@return string?
function M.table_for(lines, alias)
  local first
  local wanted = alias:lower()
  for _, line in ipairs(lines) do
    for _, kw in ipairs { "from", "join", "update", "into" } do
      for tbl, name in line:gmatch("%f[%w]" .. kw .. "%s+([%w_.]+)%s+([%w_]+)") do
        local table = tbl:gsub("%.$", "")
        first = first or table
        if not STOP[name:lower()] and (wanted == "" or name:lower() == wanted) then
          return table
        end
      end
      for tbl in line:gmatch("%f[%w]" .. kw .. "%s+([%w_.]+)%s*$") do
        local table = tbl:gsub("%.$", "")
        first = first or table
        if wanted == "" or table:lower() == wanted then
          return table
        end
      end
    end
  end
  return first
end

function M.new()
  return setmetatable({}, Source)
end

function Source:enabled()
  return vim.bo.filetype == "sql"
end

local function empty()
  return { is_incomplete_forward = false, is_incomplete_backward = false, items = {} }
end

---@param ctx blink.cmp.Context
---@param callback fun(response: table)
function Source:get_completions(ctx, callback)
  local before = ctx.line:sub(1, ctx.cursor[2])
  local what = M.context(before)
  if not what then
    return callback(empty())
  end
  local root = root_of(ctx)
  local c = require("sqlrun.connections").current(root)
  if not c or vim.fn.executable(require("sqlrun.runner").binary(c)) ~= 1 then
    return callback(empty())
  end
  local word = before:match "[%w_]*$" or ""
  local line, col = ctx.cursor[1] - 1, ctx.cursor[2]
  local range = {
    start = { line = line, character = math.max(col - #word, 0) },
    ["end"] = { line = line, character = col },
  }
  local function reply(names, kind, detail)
    local items = {}
    for _, name in ipairs(names) do
      if name:sub(1, #word):lower() == word:lower() then
        items[#items + 1] = {
          label = name,
          kind = kind,
          detail = detail,
          textEdit = { range = range, newText = name },
        }
      end
    end
    callback { is_incomplete_forward = false, is_incomplete_backward = false, items = items }
  end

  if what.kind == "tables" then
    return M.names(root, c, function(names)
      reply(names, KIND.Class, "table")
    end)
  end
  local lines = vim.api.nvim_buf_get_lines(ctx.bufnr, 0, -1, false)
  local table = what.alias and M.table_for(lines, what.alias)
    or (not what.alias and M.table_for(lines, ""))
  if not table then
    return callback(empty())
  end
  M.columns(root, c, table, function(columns)
    reply(
      vim.tbl_map(function(col)
        return col.name
      end, columns),
      KIND.Field,
      "column · " .. table
    )
  end)
end

return M
