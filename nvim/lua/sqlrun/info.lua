-- ── What this project's SQL has (the `sql://info` panel) ────────────────────
-- The connection, the dialect and the four tools that have to speak the same one (client, sqls, SQLFluff, sql-formatter),
-- what is installed, and what to do next. It is text, not a modal: it stays open next to the code and `<C-y>` copies it.
local connections = require "sqlrun.connections"
local dialects = require "sqlrun.dialects"
local runner = require "sqlrun.runner"

local M = {}

---@param name string
---@return string
local function installed(name)
  return vim.fn.executable(name) == 1 and "✓" or "✗"
end

---@param name string
---@param hint string
---@return string
local function tool(name, hint)
  if vim.fn.executable(name) == 1 then
    return ("  %s %s"):format(name, installed(name))
  end
  return ("  %s %s  %s"):format(name, installed(name), hint)
end

---@param c SqlConnection?
---@return string
local function connection_line(c)
  if not c then
    return "none · <leader>Qc opens the picker (or <leader>Qn adds one)"
  end
  return ("%s · %s · %s"):format(c.name, connections.shown(c.target), c.source)
end

---@param c SqlConnection?
---@param root string?
---@return string[]
function M.lines(c, root)
  local rows = require("core.settings").sql or {}
  local d = c and dialects.get(c.kind) or dialects.fallback()
  local label = d and d.label or "PostgreSQL"
  root = root or require("sqlrun").root()
  local out = {
    "# SQL",
    "",
    ("**Project** `%s`"):format(vim.fn.fnamemodify(root, ":~")),
    ("**Connection** %s"):format(connection_line(c)),
    ("**Dialect** `%s` (%s): client `%s` · sqls `%s` · SQLFluff `%s` · formatter `%s`"):format(
      d.id,
      label,
      d.client,
      d.sqls or "—",
      d.sqlfluff,
      d.formatter
    ),
    "",
    "## Tools",
    tool(runner.binary(c or { kind = d.id }), d.install),
    tool("sqls", ":MasonInstall sqls · go install github.com/sqls-server/sqls@latest"),
    tool("sqlfluff", ":MasonInstall sqlfluff · pipx install sqlfluff"),
    tool("sql-formatter", ":MasonInstall sql-formatter · npm i -g sql-formatter"),
    "",
    "## Keys",
    "`r` run the statement or the selection · `a` run the file · `e` explain · `E` explain analyze",
    "`s` schema browser · `t` tables · `d` describe the table under the cursor · `c` connections",
    "`i` this panel · `h` history · `n` new connection · `x` stop the query",
    "`f` format · `F` fix with SQLFluff · `p` ping · `l` the last run again",
    "",
    "## Tips",
    ("- %s"):format(d.tip),
    ("- The linter and the formatter follow the connection: SQLFluff `%s`, sql-formatter `%s`."):format(
      d.sqlfluff,
      d.formatter
    ),
  }
  if not c then
    out[#out + 1] =
      "- No connection found: put `DATABASE_URL` in `.env`, add a `.db`/`.duckdb` file, or use `<leader>Qc`."
  end
  if d.sqls == nil then
    out[#out + 1] = "- sqls cannot connect to this engine: completion of its tables is not available."
  end
  if (rows.history or 0) > 0 then
    out[#out + 1] = ("- Up to %d runs of this project are in `<leader>Qh`."):format(rows.history)
  end
  return out
end

return M
