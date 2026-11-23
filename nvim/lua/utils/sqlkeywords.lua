-- ── SQL keywords and functions (blink source, 0 tokens) ────────────────────────
-- sqls completes the real tables and columns, but its keyword list is short: `LIMIT` is not in it. Offer the words that
-- matter locally, in the dialect the project actually speaks (sqlrun/dialect.lua: forced, else from the connection).
-- No process, no files, no state — the same instant source Python gets from utils/pybuiltins.lua.
local M = {}
local KIND = vim.lsp.protocol.CompletionItemKind
local Source = {}
Source.__index = Source

-- stylua: ignore start
local COMMON = {
  "SELECT", "DISTINCT", "ALL", "AS", "FROM", "WHERE", "GROUP BY", "HAVING", "ORDER BY", "ASC", "DESC",
  "LIMIT", "OFFSET", "JOIN", "INNER JOIN", "LEFT JOIN", "RIGHT JOIN", "FULL JOIN", "CROSS JOIN", "ON", "USING",
  "UNION", "UNION ALL", "INTERSECT", "EXCEPT", "WITH", "RECURSIVE", "INSERT INTO", "VALUES", "UPDATE", "SET",
  "DELETE FROM", "CREATE TABLE", "ALTER TABLE", "DROP TABLE", "TRUNCATE TABLE", "RETURNING", "CASE", "WHEN",
  "THEN", "ELSE", "END", "AND", "OR", "NOT", "IN", "IS", "NULL", "LIKE", "BETWEEN", "EXISTS", "TRUE", "FALSE",
  "CAST", "EXPLAIN", "ANALYZE", "PRIMARY KEY", "FOREIGN KEY", "REFERENCES", "DEFAULT", "UNIQUE", "CHECK",
  "CONSTRAINT", "ADD COLUMN", "RENAME TO", "IF EXISTS", "IF NOT EXISTS", "PARTITION BY", "OVER", "ROWS", "RANGE",
  "CURRENT ROW", "UNBOUNDED PRECEDING", "UNBOUNDED FOLLOWING",
}

local FUNCTIONS = {
  "COUNT", "SUM", "AVG", "MIN", "MAX", "COALESCE", "NULLIF", "GREATEST", "LEAST", "ABS", "ROUND", "CEIL",
  "FLOOR", "LENGTH", "LOWER", "UPPER", "TRIM", "SUBSTRING", "REPLACE", "CONCAT", "NOW", "CURRENT_DATE",
  "CURRENT_TIMESTAMP", "EXTRACT", "DATE_TRUNC", "ROW_NUMBER", "RANK", "DENSE_RANK", "LAG", "LEAD", "STRING_AGG",
  "ARRAY_AGG", "JSON_AGG",
}

local PER_DIALECT = {
  postgres = {
    "ILIKE", "RETURNING", "JSONB", "JSON", "ON CONFLICT", "DO NOTHING", "DO UPDATE", "LATERAL", "FILTER", "WINDOW",
    "MATERIALIZED", "GENERATED", "IDENTITY", "SERIAL", "BIGSERIAL", "UUID", "TABLESAMPLE", "AGE", "TO_CHAR",
  },
  sqlite = {
    "PRAGMA", "AUTOINCREMENT", "GLOB", "REPLACE INTO", "ATTACH", "DETACH", "VACUUM", "WITHOUT ROWID", "STRICT",
    "JSON_EXTRACT", "JSON_EACH", "STRFTIME", "DATE", "DATETIME", "UNIXEPOCH",
  },
  mysql = {
    "DUPLICATE KEY", "ENGINE", "AUTO_INCREMENT", "STRAIGHT_JOIN", "REGEXP", "RLIKE", "USE", "SHOW TABLES",
    "DESCRIBE", "IFNULL", "GROUP_CONCAT", "UNIX_TIMESTAMP", "DATE_FORMAT",
  },
  mariadb = {
    "DUPLICATE KEY", "ENGINE", "AUTO_INCREMENT", "STRAIGHT_JOIN", "REGEXP", "RLIKE", "USE", "SHOW TABLES",
    "DESCRIBE", "IFNULL", "GROUP_CONCAT", "UNIX_TIMESTAMP", "DATE_FORMAT",
  },
  sqlserver = {
    "TOP", "NOLOCK", "OUTER APPLY", "CROSS APPLY", "FETCH NEXT", "ROWS ONLY", "IDENTITY", "NVARCHAR", "GETDATE",
    "ISNULL", "TRY_CAST", "PIVOT", "UNPIVOT", "WITH TIES",
  },
  duckdb = {
    "QUALIFY", "PIVOT", "UNPIVOT", "SAMPLE", "INSTALL", "LOAD", "SUMMARIZE", "LIST", "STRUCT", "READ_CSV",
    "PARQUET_SCAN", "EPOCH",
  },
}
-- stylua: ignore end

--- Every word for a dialect, keywords first, then functions, then the dialect's own (pure, stable order).
---@param dialect string?
---@return string[]
function M.words(dialect)
  local out, seen = {}, {}
  local function add(list)
    for _, word in ipairs(list) do
      if not seen[word] then
        seen[word] = true
        out[#out + 1] = word
      end
    end
  end
  add(COMMON)
  add(FUNCTIONS)
  add(PER_DIALECT[dialect or ""] or {})
  return out
end

--- Whether what precedes the cursor is a string or a comment: leave those to the editor, not to completion.
---@param before string
---@return boolean
function M.junk_context(before)
  local i, n = 1, #before
  local quote, block = nil, false
  while i <= n do
    local c, c2 = before:sub(i, i), before:sub(i, i + 1)
    if block then
      if c2 == "*/" then
        block = false
        i = i + 2
      else
        i = i + 1
      end
    elseif quote then
      if c == "\\" then
        i = i + 2
      elseif c == quote then
        if c2 == quote then -- SQL escapes a quote by doubling it
          i = i + 2
        else
          quote = nil
          i = i + 1
        end
      else
        i = i + 1
      end
    elseif c2 == "--" then
      return true
    elseif c2 == "/*" then
      block = true
      i = i + 2
    elseif c == "'" or c == '"' then
      quote = c
      i = i + 1
    else
      i = i + 1
    end
  end
  return quote ~= nil or block
end

local cache = {}

---@param dialect string?
---@return string[]
local function cached_words(dialect)
  if not cache[dialect] then
    cache[dialect] = M.words(dialect)
  end
  return cache[dialect]
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
  -- `table.` is a column (sqls' job), a string or a comment is not code
  if before:match "%.$" or M.junk_context(before) then
    return callback(empty())
  end
  local word = before:match "[%w_]*$" or ""
  if word == "" then
    return callback(empty())
  end
  local dialect = require("sqlrun").dialect()
  local line, col = ctx.cursor[1] - 1, ctx.cursor[2]
  local range = {
    start = { line = line, character = math.max(col - #word, 0) },
    ["end"] = { line = line, character = col },
  }
  local items = {}
  for _, name in ipairs(cached_words(dialect)) do
    if name:sub(1, #word):lower() == word:lower() then
      items[#items + 1] = {
        label = name,
        kind = KIND.Keyword,
        detail = "keyword",
        textEdit = { range = range, newText = name },
      }
    end
  end
  callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = items })
end

return M
