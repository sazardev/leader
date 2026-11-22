-- Tests for the 0-token Python data helpers (utils/pyimports.lua, utils/pydata.lua and their blink sources).
-- Hermetic: temporary files and buffers, no uv, no pandas, no network.
local fails = 0
local function print(...)
  io.stdout:write(table.concat(vim.tbl_map(tostring, { ... }), "\t"), "\n")
end
local function eq(name, got, want)
  if vim.deep_equal(got, want) then
    print("ok   " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. "\n  got:  " .. vim.inspect(got) .. "\n  want: " .. vim.inspect(want))
  end
end
local function ok(name, value, message)
  if value then
    print("ok   " .. name)
  else
    fails = fails + 1
    print("FAIL " .. name .. (message and ("\n  " .. message) or ""))
  end
end

local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
package.path = "/home/sazar/Documents/my-nvim-setup/nvim/lua/?.lua;/home/sazar/Documents/my-nvim-setup/nvim/lua/?/init.lua;"
  .. package.path

local imports = require("utils.pyimports")
local data = require("utils.pydata")

-- ── import catalog ────────────────────────────────────────────────────────────
local pd = imports.matches("pd")
ok("catalog: pd matches pandas", #pd >= 1 and pd[1].row.line == "import pandas as pd")
eq("catalog: too short is quiet", #imports.matches("p"), 0)
local split = imports.matches("train")
ok(
  "catalog: sklearn symbol",
  #split >= 1 and split[1].row.line == "from sklearn.model_selection import train_test_split"
)
ok(
  "catalog: package hint when missing",
  imports.matches("sns", { seaborn = false })[1].detail:find("uv add seaborn", 1, true) ~= nil
)
ok("catalog: bundles", #imports.bundles() >= 4)

-- ── insertion point ───────────────────────────────────────────────────────────
eq("insert_row: empty file", imports.insert_row({}), 0)
eq("insert_row: plain code", imports.insert_row({ 'print("hi")' }), 0)
eq("insert_row: after imports", imports.insert_row({ "import os", "from pathlib import Path", "", "print('hi')" }), 2)
eq("insert_row: after module docstring", imports.insert_row({ '"""Demo."""', "", "import os", "x = 1" }), 3)
eq(
  "insert_row: after multiline docstring and __future__",
  imports.insert_row({ '"""Demo.', "more", '"""', "from __future__ import annotations", "x = 1" }),
  4
)
eq("has: exact statement", imports.has({ "import os", "import pandas as pd" }, "import pandas as pd"), true)
eq("has: whitespace tolerant", imports.has({ "  import pandas as pd  " }, "import pandas as pd"), true)

-- applying twice is idempotent
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'print("hi")' })
local added = imports.apply(buf, { "numpy", "pandas", "numpy" })
eq("apply: added once each", added, { "import numpy as np", "import pandas as pd" })
eq("apply: lines in buffer", vim.api.nvim_buf_get_lines(buf, 0, -1, false), {
  "import numpy as np",
  "import pandas as pd",
  'print("hi")',
})
eq("apply: idempotent", imports.apply(buf, { "numpy", "pandas" }), {})

-- ── pure parsers ──────────────────────────────────────────────────────────────
eq("separator: comma", data.separator("a,b,c"), ",")
eq("separator: tab", data.separator("a\tb\tc"), "\t")
eq("separator: semicolon", data.separator("a;b;c"), ";")
eq(
  "delimited: quoted comma",
  data.columns_delimited('name,amount,note\n"Doe, John",10,"hi, there"'),
  { "name", "amount", "note" }
)
eq("json: top-level object", data.columns_json('{"total":1,"name":"x"}'), { "total", "name" })
eq(
  "json: array of objects (no nested keys)",
  data.columns_json('[{"total":1,"nested":{"a":2}}]'),
  { "total", "nested" }
)
eq("json: json lines", data.columns_json('{"a":1}\n{"b":2}'), { "a" })
eq("markdown: pipe table", data.columns_markdown("| Name | Total |\n| --- | ---: |\n| a | 1 |"), { "Name", "Total" })
eq(
  "sql: select list with alias",
  data.columns_sql("SELECT order_id, total AS amount FROM sales"),
  { "order_id", "amount" }
)
eq("sql: qualified column", data.columns_sql("select s.total, s.active from sales s"), { "total", "active" })
eq("sql: star has no columns", data.columns_sql("SELECT * FROM sales"), {})

-- ── real files ────────────────────────────────────────────────────────────────
local function write(rel, text)
  vim.fn.mkdir(vim.fs.dirname(root .. "/" .. rel), "p")
  local file = assert(io.open(root .. "/" .. rel, "wb"))
  file:write(text)
  file:close()
  return root .. "/" .. rel
end
local csv = write("data/sales.csv", "order_id,total,created_at,active\n1,12.5,2026-01-02,true\n2,3,2026-01-03,false\n")
local info = data.columns(csv)
eq("columns: csv names", info.columns, { "order_id", "total", "created_at", "active" })
eq("columns: csv types", info.types, {
  order_id = "int",
  total = "float",
  created_at = "date",
  active = "bool",
})
ok("columns: cached", data.columns(csv) == info)
local js = write("data/people.json", '[{"name":"Ada","age":36},{"name":"Lin","age":41}]')
eq("columns: json file", data.columns(js).columns, { "name", "age" })
local md = write("data/table.md", "| City | Count |\n| --- | --- |\n| MX | 3 |")
eq("columns: markdown file", data.columns(md).columns, { "City", "Count" })

-- stat change invalidates the cache
write("data/sales.csv", "a,b\n1,2\n")
eq("columns: cache follows mtime/size", data.columns(csv).columns, { "a", "b" })

-- ── string / call contexts ────────────────────────────────────────────────────
ok("string_context: inside", data.string_context('df = pd.read_csv("data/sa'))
eq("string_context: inside start", select(2, data.string_context('df = pd.read_csv("data/sa')), 18)
eq("string_context: closed quote", data.string_context('df = pd.read_csv("data/x.csv")'), false)

-- assignments from a buffer
local code = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(code, root .. "/analysis.py")
vim.api.nvim_buf_set_lines(code, 0, -1, false, {
  "import pandas as pd",
  "",
  'df = pd.read_csv("data/sales.csv")',
  "print(df['total'])",
})
local assignments = data.assignments(code, 4)
ok("assignments: reader + resolved path", assignments.df and assignments.df.path == csv, vim.inspect(assignments))

-- ── blink sources ─────────────────────────────────────────────────────────────
local function complete(source, line, col, bufnr, row)
  local captured
  source:get_completions({
    bufnr = bufnr or 0,
    cursor = { row or 1, col or #line },
    line = line,
  }, function(result)
    captured = result
  end)
  return captured
end

vim.api.nvim_set_current_buf(code)
local pyimports_source = require("utils.pysmart").new()
local r = complete(pyimports_source, "pd", 2, code)
ok(
  "pysmart: pd offers pandas",
  r and #r.items > 0 and r.items[1].data.import == "import pandas as pd",
  vim.inspect(r and r.items)
)
eq("pysmart: quiet inside a string", #complete(pyimports_source, 'x = "pd', 7, code).items, 0)

vim.api.nvim_buf_set_lines(code, 0, -1, false, {
  "import pandas as pd",
  'df = pd.read_csv("data/sales.csv")',
  'print(df["a',
})
local pydata_source = require("utils.pydata").new()
local columns = complete(pydata_source, 'print(df["a', 11, code, 3)
ok(
  "pydata: column completion",
  columns and #columns.items > 0 and columns.items[1].label == "a",
  vim.inspect(columns and columns.items)
)

vim.api.nvim_buf_set_lines(code, 0, -1, false, {
  "import pandas as pd",
  'df = pd.read_sql("SELECT order_id, total FROM sales", con)',
  'print(df["to',
})
local sqlcols = complete(pydata_source, 'print(df["to', 11, code, 3)
ok(
  "pydata: sql query columns",
  sqlcols and #sqlcols.items == 1 and sqlcols.items[1].label == "total",
  vim.inspect(sqlcols and sqlcols.items)
)

vim.api.nvim_buf_set_lines(code, 0, -1, false, { 'df = pd.read_csv("data/' })
local paths = complete(pydata_source, 'df = pd.read_csv("data/', 23, code, 1)
ok("pydata: path completion", paths and #paths.items > 0, vim.inspect(paths and paths.items))
ok(
  "pydata: csv files under data/",
  #paths.items >= 1 and paths.items[1].label == "sales.csv",
  vim.inspect(vim.tbl_map(function(i)
    return i.label
  end, paths.items))
)

if fails > 0 then
  print("FAILURES: " .. fails)
else
  print("ALL OK")
end
vim.cmd("qa!")
