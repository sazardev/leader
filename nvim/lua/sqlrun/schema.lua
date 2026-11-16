-- ── Schema browser ───────────────────────────────────────────────────────────
-- The tables of the connection (<leader>Qs) and the columns of one. The query is per dialect (each file under
-- sqlrun/dialects has `schema_tables`/`schema_columns`), always the same tab-separated shape, so parsing is one function:
-- `schema`, `name`, `kind`, `columns` for a table and `name`, `type`, `null`, `default` for a column. The parsers are
-- pure (test-langs.lua); the picker only decides what to do with what came back.
local dialects = require "sqlrun.dialects"
local diagnose = require "sqlrun.diagnose"
local runner = require "sqlrun.runner"
local results = require "sqlrun.results"
local log = require "utils.log"

local M = {}

---@param output string?
---@return string[][]
local function rows(output)
  local out = {}
  for line in (output or ""):gmatch "[^\r\n]+" do
    if line ~= "" and not line:match "^%(" then
      local cols = vim.split(line, "\t", { plain = true })
      if #cols >= 1 and vim.trim(cols[1]) ~= "" then
        out[#out + 1] = cols
      end
    end
  end
  return out
end

---@class SqlTable
---@field schema string
---@field name string
---@field kind string
---@field columns integer?

--- @param output string?
--- @return SqlTable[]
function M.tables(output)
  local out = {}
  for _, cols in ipairs(rows(output)) do
    if #cols >= 3 then
      out[#out + 1] = {
        schema = cols[1],
        name = cols[2],
        kind = cols[3],
        columns = tonumber(cols[4]),
      }
    end
  end
  return out
end

---@class SqlColumn
---@field name string
---@field type string
---@field nullable string
---@field default string
---@field pk integer?

--- @param output string?
--- @return SqlColumn[]
function M.columns(output)
  local out = {}
  for _, cols in ipairs(rows(output)) do
    if #cols >= 3 then
      out[#out + 1] = {
        name = cols[1],
        type = cols[2],
        nullable = cols[3],
        default = cols[4] or "",
        pk = tonumber(cols[5]),
      }
    end
  end
  return out
end

--- The name to show in the picker (SQLite's `main` is implicit)
---@param table SqlTable
---@return string
function M.label(table)
  if table.schema == "" or table.schema == "main" then
    return table.name
  end
  return table.schema .. "." .. table.name
end

--- @param text string
--- @param width integer
--- @return string
local function pad(text, width)
  return text .. (" "):rep(math.max(width - vim.fn.strdisplaywidth(text), 0))
end

--- The columns as a small table; `default` keeps the expression the database reports
---@param tbl SqlTable
---@param columns SqlColumn[]
---@return string[]
function M.format(tbl, columns)
  local lines = {
    ("-- %s · %s · %d column%s"):format(M.label(tbl), tbl.kind, #columns, #columns == 1 and "" or "s"),
  }
  if #columns == 0 then
    lines[#lines + 1] = "-- no columns"
    return lines
  end
  local pk = false
  for _, c in ipairs(columns) do
    pk = pk or (c.pk or 0) > 0
  end
  local head = { "name", "type", "null", "default" }
  if pk then
    head[#head + 1] = "pk"
  end
  local width = {}
  for i, name in ipairs(head) do
    width[i] = vim.fn.strdisplaywidth(name)
  end
  for _, c in ipairs(columns) do
    local values = { c.name, c.type, c.nullable, c.default }
    if pk then
      values[#values + 1] = (c.pk or 0) > 0 and "yes" or ""
    end
    for i, value in ipairs(values) do
      width[i] = math.max(width[i], vim.fn.strdisplaywidth(value))
    end
  end
  local function line(values)
    local parts = {}
    for i, value in ipairs(values) do
      parts[#parts + 1] = pad(value, width[i])
    end
    return (table.concat(parts, "  "):gsub("%s+$", ""))
  end
  lines[#lines + 1] = line(head)
  local dashes = {}
  for i = 1, #head do
    dashes[i] = ("-"):rep(width[i])
  end
  lines[#lines + 1] = line(dashes)
  for _, c in ipairs(columns) do
    local values = { c.name, c.type, c.nullable, c.default }
    if pk then
      values[#values + 1] = (c.pk or 0) > 0 and "yes" or ""
    end
    lines[#lines + 1] = line(values)
  end
  return lines
end

--- Runs a schema query and hands back its rows; the error is already a sentence (plus the client's hint)
---@param c SqlConnection
---@param root string
---@param sql string
---@param parse fun(output: string?): table[]
---@param cb fun(rows: table[]?, problem: string?)
function M.fetch(c, root, sql, parse, cb)
  local handle, problem = runner.query(c, sql, { cwd = root }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        local first = diagnose.first_line(res.stderr)
        local tip = diagnose.tip(res.stderr)
        return cb(nil, (first ~= "" and first or "the query failed") .. (tip and (" · " .. tip) or ""))
      end
      cb(parse(res.stdout), nil)
    end)
  end)
  if not handle then
    local tip = runner.install(c)
    cb(nil, (problem or "could not start the client") .. (tip ~= "" and (" · " .. tip) or ""))
  end
end

---@param c SqlConnection
---@param root string
---@param cb fun(tables: SqlTable[]?, problem: string?)
function M.tables_of(c, root, cb)
  local d = dialects.get(c.kind)
  if not d then
    return cb(nil, "unknown dialect " .. c.kind)
  end
  M.fetch(c, root, d.schema_tables(c), M.tables, cb)
end

---@param c SqlConnection
---@param root string
---@param table SqlTable
---@param cb fun(columns: SqlColumn[]?, problem: string?)
function M.columns_of(c, root, table, cb)
  local d = dialects.get(c.kind)
  if not d then
    return cb(nil, "unknown dialect " .. c.kind)
  end
  M.fetch(c, root, d.schema_columns(c, table.schema, table.name), M.columns, cb)
end

--- Puts the table name at the cursor (the picker's `<C-y>`)
---@param table SqlTable
function M.insert(table)
  vim.api.nvim_put({ table.name }, "c", true, true)
end

--- Shows one table's columns in the results split
---@param c SqlConnection
---@param root string
---@param table SqlTable
function M.describe(c, root, table)
  M.columns_of(c, root, table, function(columns, problem)
    if not columns then
      return log.warn("SQL: " .. (problem or "could not read the columns"))
    end
    results.show {
      name = "sql://results",
      lines = M.format(table, columns),
      rerun = function()
        M.describe(c, root, table)
      end,
    }
  end)
end

--- The tables of the connection, as a picker: Enter describes, `<C-y>` inserts the name
---@param c SqlConnection
---@param root string
function M.pick(c, root)
  M.tables_of(c, root, function(tables, problem)
    if not tables then
      return log.warn("SQL: " .. (problem or "could not read the schema"))
    end
    if #tables == 0 then
      return log.info "SQL: this connection has no tables"
    end
    require("tasks.picker").choose(
      vim.tbl_map(function(table)
        local desc = table.kind
        if table.columns then
          desc = ("%s · %d column%s"):format(table.kind, table.columns, table.columns == 1 and "" or "s")
        end
        return {
          label = M.label(table),
          desc = desc,
          value = table,
          search = table.schema .. " " .. table.name,
        }
      end, tables),
      {
        title = "SQL schema · " .. c.name,
        hint = "Enter describe · C-y insert name",
        width = 32,
        maps = {
          {
            "<C-y>",
            function(table)
              M.insert(table)
            end,
          },
        },
      },
      function(table)
        M.describe(c, root, table)
      end
    )
  end)
end

return M
