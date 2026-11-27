-- Tests for the Python helpers (utils/python.lua: module paths, pyproject scripts, versions, the venv and the entry
-- points; servers/basedpyright_prewarm.lua: the aliases to warm). Hermetic: temporary project directories, no uv,
-- pytest, LSP or network.
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

local py = require "utils.python"

-- ── pure ───────────────────────────────────────────────────────────────────
eq("module_for: src package module", py.module_for("/r", "/r/src/pkg/mod.py"), "pkg.mod")
eq("module_for: root package module", py.module_for("/r", "/r/pkg/mod.py"), "pkg.mod")
eq("module_for: package __init__", py.module_for("/r", "/r/pkg/__init__.py"), "pkg")
eq("module_for: src package __main__", py.module_for("/r", "/r/src/pkg/__main__.py"), "pkg")
eq("module_for: root __main__", py.module_for("/r", "/r/__main__.py"), "")
eq("module_for: single file", py.module_for("/r", "/r/main.py"), "main")
eq("module_for: outside the project", py.module_for("/r", "/other/main.py"), nil)
eq("module_for: folder that is not an identifier", py.module_for("/r", "/r/my-pkg/mod.py"), nil)
eq("module_for: no file", py.module_for("/r", ""), nil)
eq("is_script: PEP 723 header", py.is_script '# /// script\n# requires-python = ">=3.12"\n# ///', true)
eq("is_script: a normal file", py.is_script "print('hi')", false)
eq("tools: basedpyright", vim.tbl_contains(py.TOOLS, "basedpyright"), true)
eq("tools: debugpy", vim.tbl_contains(py.TOOLS, "debugpy"), true)
eq("data stack: pandas 2 (the book)", vim.tbl_contains(py.DATA.runtime, "pandas<3"), true)
eq("data stack: JupyterLab", vim.tbl_contains(py.DATA.runtime, "jupyterlab"), true)
eq("data stack: Excel", vim.tbl_contains(py.DATA.runtime, "openpyxl"), true)
eq("data stack: HDF5", vim.tbl_contains(py.DATA.runtime, "tables"), true)
eq("data stack: pytest-cov", vim.tbl_contains(py.DATA.dev, "pytest-cov"), true)

-- basedpyright prewarm: one completion position after each imported alias (pure, no LSP)
local prewarm = require "servers.basedpyright_prewarm"
local imported = {
  "import pandas as pd",
  "import matplotlib.pyplot as plt",
  "from numpy import array as arr",
  "def f():",
  "    xpd.not_an_alias()",
  "    pd.read_csv('x')",
  "    plt.figure()",
  "    arr.T",
}
eq("prewarm: aliases and positions", prewarm.targets(imported), {
  { alias = "pd", line = 5, character = 7 },
  { alias = "plt", line = 6, character = 8 },
  { alias = "arr", line = 7, character = 8 },
})
eq("prewarm: limit", #prewarm.targets(imported, 2), 2)
eq("prewarm: no imports", prewarm.targets { "print('x')" }, {})
eq("prewarm: from-import without as", prewarm.targets { "from math import sqrt", "x = sqrt.pi" }, {
  { alias = "sqrt", line = 1, character = 9 },
})

-- Python import aliases and the instant attribute completions (pure)
local imports = require "utils.pyimports"
local attrs = require "utils.pyattrs"
eq("aliases: dotted and simple", imports.aliases {
  "import pandas as pd",
  "import matplotlib.pyplot as plt",
  "import os",
  "from numpy import array as arr",
  "from pathlib import Path",
}, { pd = "pandas", plt = "matplotlib.pyplot", os = "os", arr = "numpy.array", Path = "pathlib.Path" })
eq("attrs: exported names", attrs.parse(table.concat({
  "from x import (",
  "    alpha,",
  "    beta as gamma,",
  ")",
  "from y import delta",
  "def phi(): pass",
  "async def chi(): pass",
  "class Kappa: pass",
  "_private = 1",
}, "\n")), { "alpha", "beta", "delta", "phi", "chi", "Kappa" })

eq("attrs: DataFrame variable", attrs.variables({
  "import pandas as pd",
  "df = pd.read_csv('data.csv')",
  "s = pd.Series([1, 2])",
  "local = other.read_csv('x')",
}, { pd = "pandas" }), { df = "pandas.DataFrame", s = "pandas.Series" })
eq("attrs: class members", attrs.class_members(table.concat({
  "class Other:",
  "    def other(self): pass",
  "",
  "class DataFrame:",
  "    def groupby(self): pass",
  "    def head(self): pass",
  "    def groupby(self): pass",
  "",
  "def outside(): pass",
}, "\n"), "DataFrame"), { "groupby", "head" })

local builtins = require "utils.pybuiltins"
for _, word in ipairs { "print", "len", "range", "for", "if", "None" } do
  eq("builtins: " .. word, vim.tbl_contains(builtins.words(), word), true)
end
local got_builtins
builtins.new():get_completions({ line = "    pri", cursor = { 1, 7 }, bufnr = 0 }, function(r) got_builtins = r end)
eq("builtins: print suggested", vim.tbl_contains(vim.tbl_map(function(i) return i.label end, got_builtins.items), "print"), true)
local got_attr
builtins.new():get_completions({ line = "pd.pr", cursor = { 1, 5 }, bufnr = 0 }, function(r) got_attr = r end)
eq("builtins: attributes left to pyattrs", #got_attr.items, 0)

-- ── fixtures on disk ───────────────────────────────────────────────────────
local root = vim.fn.tempname()
local function write(rel, lines)
  vim.fn.mkdir(vim.fs.dirname(root .. "/" .. rel), "p")
  vim.fn.writefile(lines, root .. "/" .. rel)
end

local p = root .. "/demo"
write("demo/pyproject.toml", {
  "[project]",
  'name = "demo"',
  'requires-python = ">=3.12"',
  "",
  "[project.scripts]",
  'hello = "demo.cli:main"',
  '"my-tool" = "demo.cli:run"',
  "",
  "[tool.poetry.scripts]",
  'poetry-tool = "demo.poetry:main"',
})
write("demo/src/demo/__main__.py", { "" })
write("demo/main.py", { "from fastapi import FastAPI", "", "app = FastAPI()" })
write("demo/app.py", { "import streamlit as st", "", "st.title('demo')" })
write("demo/manage.py", { "import django" })

eq("root: the pyproject folder", py.root(p), p)
eq("root: from a subfolder", py.root(p .. "/src/demo"), p)
eq("has_pyproject", py.has_pyproject(p), true)
eq("python_version: requires-python", py.python_version(p), "3.12")
eq("scripts: project.scripts and tool.poetry.scripts", py.scripts(p), {
  { name = "hello", target = "demo.cli:main", section = "project.scripts" },
  { name = "my-tool", target = "demo.cli:run", section = "project.scripts" },
  { name = "poetry-tool", target = "demo.poetry:main", section = "tool.poetry.scripts" },
})
eq("uv_project: no lockfile", py.uv_project(p), false)
eq("venv: none yet", py.venv(p), nil)

-- `.python-version` wins over requires-python
write("demo/.python-version", { "3.11" })
eq("python_version: .python-version first", py.python_version(p), "3.11")

-- The project's venv is used when there is no uv.lock
write("demo/.venv/bin/python", { "#!/bin/sh", "exit 0" })
vim.fn.setfperm(p .. "/.venv/bin/python", "rwxr-xr-x")
eq("venv: .venv detected", py.venv(p), p .. "/.venv")
eq("python: the .venv interpreter", py.python(p), vim.fn.shellescape(p .. "/.venv/bin/python"))
vim.fn.delete(p .. "/.venv", "rf")

-- ── entry points ───────────────────────────────────────────────────────────
local by_cmd = {}
for _, item in ipairs(py.entrypoints(p)) do
  by_cmd[item.cmd] = item
end
local function has(name, cmd)
  eq(name, by_cmd[cmd] ~= nil, true)
end
has("entrypoints: console script (callable)", "python3 -c 'from demo.cli import main; main()'")
has("entrypoints: quoted console script", "python3 -c 'from demo.cli import run; run()'")
has("entrypoints: poetry script", "python3 -c 'from demo.poetry import main; main()'")
has("entrypoints: package __main__", "python3 -m demo")
has("entrypoints: Django", "python3 manage.py runserver")
has("entrypoints: FastAPI", "uvicorn main:app --reload")
eq("entrypoints: Streamlit path", by_cmd["streamlit run " .. vim.fn.shellescape(p .. "/app.py")] ~= nil, true)
eq("entrypoints: FastAPI label", by_cmd["uvicorn main:app --reload"].label, "FastAPI dev server")
eq("entrypoints: plain script is not added twice", by_cmd["python3 " .. p .. "/main.py"], nil)

-- ── uv project ─────────────────────────────────────────────────────────────
write("demo/uv.lock", { "" })
eq("uv_project: lockfile", py.uv_project(p), true)
if vim.fn.executable "uv" == 1 then
  local cmds = {}
  for _, item in ipairs(py.entrypoints(p)) do
    cmds[item.cmd] = true
  end
  eq("entrypoints: console scripts run through uv", cmds["uv run " .. vim.fn.shellescape "hello"], true)
  eq("entrypoints: hyphenated console script", cmds["uv run " .. vim.fn.shellescape "my-tool"], true)
end

-- ── project files ──────────────────────────────────────────────────────────
write("demo/ruff.toml", { "line-length = 120" })
local labels = vim.tbl_map(function(item)
  return item.label
end, py.project_files(p))
eq("project_files: canonical order", labels, { "pyproject.toml", "uv.lock", ".python-version", "ruff.toml" })

-- ── pretty output ──────────────────────────────────────────────────────────
local pypretty = require "utils.pypretty"
eq("pypretty: the runner ships next to the module", vim.fn.filereadable(pypretty.runner()), 1)
local pretty_cmd = pypretty.command("uv run python", "/r/src/my pkg/mod.py")
eq("pypretty: keeps the project's interpreter", vim.startswith(pretty_cmd, "uv run python "), true)
eq("pypretty: runs the runner", pretty_cmd:find("runner.py", 1, true) ~= nil, true)
eq("pypretty: quotes the script", vim.endswith(pretty_cmd, vim.fn.shellescape "/r/src/my pkg/mod.py"), true)
eq(
  "pypretty: a venv interpreter is passed through",
  vim.startswith(pypretty.command("'/p/.venv/bin/python'", "/r/a.py"), "'/p/.venv/bin/python' "),
  true
)
eq(
  "pypretty: theme and traceback flags",
  pypretty.command("python3", "/r/a.py", { light = true, locals = true }),
  "python3 " .. vim.fn.shellescape(pypretty.runner()) .. " --light --locals " .. vim.fn.shellescape "/r/a.py"
)
eq(
  "pypretty: no flags when both are off",
  pypretty.command("python3", "/r/a.py", { light = false, locals = false }),
  "python3 " .. vim.fn.shellescape(pypretty.runner()) .. " " .. vim.fn.shellescape "/r/a.py"
)
eq(
  "pypretty: the clear flag",
  pypretty.command("python3", "/r/a.py", { clear = false }),
  "python3 " .. vim.fn.shellescape(pypretty.runner()) .. " --no-clear " .. vim.fn.shellescape "/r/a.py"
)
eq(
  "pypretty: the plots flag",
  pypretty.command("python3", "/r/a.py", { plots = false }),
  "python3 " .. vim.fn.shellescape(pypretty.runner()) .. " --no-plots " .. vim.fn.shellescape "/r/a.py"
)

-- ── the menu ───────────────────────────────────────────────────────────────
local ok, maps = pcall(require, "languages.actions.python")
if not ok then
  fails = fails + 1
  print("FAIL menu: " .. tostring(maps))
else
  local keys, seen = {}, {}
  for _, m in ipairs(maps) do
    if type(m[1]) ~= "string" or type(m[2]) ~= "string" or m[2] == "" then
      fails = fails + 1
      print("FAIL menu: malformed entry " .. vim.inspect(m))
    end
    if seen[m[1]] then
      fails = fails + 1
      print("FAIL menu: duplicate key " .. m[1])
    end
    seen[m[1]] = true
    keys[m[1]] = true
  end
  eq("command: PythonDoctor", vim.fn.exists ":PythonDoctor", 2)
  eq("command: PythonInit", vim.fn.exists ":PythonInit", 2)
  for _, key in ipairs {
    "r",
    "p",
    "l",
    "i",
    "I",
    "j",
    "b",
    "a",
    "d",
    "R",
    "u",
    "U",
    "t",
    "v",
    "x",
    "f",
    "o",
    "y",
    "c",
    "e",
    "Pi",
    "Pv",
    "Pp",
    "Pr",
    "Po",
    "Px",
    "Pf",
    "Pk",
    "m",
    "M",
    "A",
    "Dd",
    "Dt",
    "Sr",
    "Sp",
  } do
    eq("menu: " .. key, keys[key], true)
  end
end

vim.fn.delete(root, "rf")
print(fails == 0 and "\nALL OK" or ("\nFAILURES: " .. fails))
vim.cmd(fails == 0 and "qa!" or "cquit 1")
