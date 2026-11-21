-- Tests for the Python project helpers (utils/python.lua): module paths, pyproject scripts, versions, the venv and the
-- entry points (scripts, __main__.py, Django, FastAPI, Flask, Streamlit, plain scripts). Hermetic: temporary project
-- directories, no uv, pytest or network.
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
