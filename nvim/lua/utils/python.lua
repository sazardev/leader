-- ── Python project helpers ───────────────────────────────────────────────────
-- One place that knows how a Python project is laid out (pyproject.toml, src/, .venv), how it is run (uv, the
-- project's venv, python3) and which entry points it exposes ([project.scripts], __main__.py, main.py, manage.py,
-- FastAPI/Flask/Streamlit apps). Pure reads: nothing here starts a process.
local M = {}

local project = require "utils.project"

M.MARKERS = { "pyproject.toml", "pytest.ini", "setup.cfg", "tox.ini", "setup.py", "requirements.txt", ".git" }

--- Editor tools the Python menu needs (Mason package names)
M.TOOLS = { "ruff", "basedpyright", "debugpy" }

--- The "Data analysis" starter: the pandas book's stack, the I/O extras its chapters use, and the dev tools
M.DATA = {
  runtime = {
    "pandas<3", -- the 2022 book's pandas 2.x; `uv add 'pandas>=3'` upgrades it
    "numpy",
    "matplotlib",
    "scipy",
    "statsmodels",
    "scikit-learn",
    "pyarrow",
    "jupyterlab",
    "ipython",
    "ipykernel",
    "openpyxl",
    "xlrd",
    "lxml",
    "html5lib",
    "beautifulsoup4",
    "sqlalchemy",
    "tables",
    "requests",
  },
  dev = { "pytest", "pytest-cov", "ruff" },
}

local SKIP_DIRS = {
  [".git"] = true,
  [".venv"] = true,
  ["venv"] = true,
  ["__pycache__"] = true,
  ["node_modules"] = true,
  ["build"] = true,
  ["dist"] = true,
  ["tests"] = true,
  ["test"] = true,
  ["docs"] = true,
  ["examples"] = true,
  [".tox"] = true,
  [".nox"] = true,
  ["site-packages"] = true,
}

local PROJECT_FILES = {
  { "pyproject.toml", "metadata, dependencies, tool config" },
  { "uv.lock", "resolved versions (uv)" },
  { ".python-version", "pinned Python" },
  { "ruff.toml", "ruff: lint and format" },
  { ".ruff.toml", "ruff: lint and format" },
  { "pytest.ini", "pytest" },
  { "tox.ini", "tox / pytest" },
  { "setup.cfg", "legacy packaging / tool config" },
  { "requirements.txt", "pip requirements" },
  { "Makefile", "project tasks (<leader>R)" },
  { "Dockerfile", "container image" },
  { "docker-compose.yml", "services" },
  { "docker-compose.yaml", "services" },
  { ".env", "environment variables" },
}

--- Directory of the current buffer's project, or the root above `dir`
---@param dir? string
---@return string
function M.root(dir)
  return vim.fs.root(dir or 0, M.MARKERS) or (dir or project.file_dir())
end

---@param path string
---@return string?
function M.read(path)
  return project.read(path)
end

---@param root string
---@return boolean
function M.uv_project(root)
  return vim.uv.fs_stat(root .. "/uv.lock") ~= nil
end

---@param root string
---@return boolean
function M.has_pyproject(root)
  return vim.uv.fs_stat(root .. "/pyproject.toml") ~= nil
end

--- The project's virtual environment (`.venv` first, then `venv`), if it has an interpreter
---@param root string
---@return string?
function M.venv(root)
  for _, dir in ipairs { ".venv", "venv" } do
    for _, bin in ipairs { "/bin/python", "/Scripts/python.exe" } do
      if vim.fn.executable(root .. "/" .. dir .. bin) == 1 then
        return root .. "/" .. dir
      end
    end
  end
end

---@param root string
---@return string?
function M.venv_python(root)
  local venv = M.venv(root)
  if not venv then
    return nil
  end
  local win = vim.fn.has "win32" == 1
  return venv .. (win and "/Scripts/python.exe" or "/bin/python")
end

--- The interpreter command of the project: `uv run python`, the .venv's python, or python3
---@param root string
---@return string
function M.python(root)
  if vim.fn.executable "uv" == 1 and M.uv_project(root) then
    return "uv run python"
  end
  local venv = M.venv_python(root)
  if venv then
    return vim.fn.shellescape(venv)
  end
  return "python3"
end

--- Is this a PEP 723 script? (a `# /// script` header with its inline dependencies)
---@param text string
---@return boolean
function M.is_script(text)
  return text:find("# /// script", 1, true) ~= nil
end

--- The Python version the project asks for: `.python-version`, else pyproject's requires-python
---@param root string
---@return string?
function M.python_version(root)
  local pinned = (M.read(root .. "/.python-version") or ""):match "(%d+%.%d+)"
  if pinned then
    return pinned
  end
  local text = M.read(root .. "/pyproject.toml") or ""
  return text:match 'requires%-python%s*=%s*"[%s><=~^]*([%d]+%.%d+)'
end

--- `[project.scripts]`, `[project.gui-scripts]` and `[tool.poetry.scripts]` of pyproject.toml
---@param root string
---@return { name: string, target: string, section: string }[]
function M.scripts(root)
  local text = M.read(root .. "/pyproject.toml") or ""
  local out, seen = {}, {}
  local section
  for line in (text .. "\n"):gmatch "([^\n]*)\n" do
    local header = line:match "^%s*%[([^%]]+)%]%s*$"
    if header then
      section = header
    elseif section == "project.scripts" or section == "project.gui-scripts" or section == "tool.poetry.scripts" then
      local name, target = line:match '^%s*"?([%w%._%-]+)"?%s*=%s*"([^"]+)"'
      if name and target and not seen[name] then
        seen[name] = true
        out[#out + 1] = { name = name, target = target, section = section }
      end
    end
  end
  return out
end

--- The module a file belongs to (`src/pkg/mod.py` → `pkg.mod`); "" for a root __main__.py, nil outside the project
--- or for a folder that is not a valid module name.
---@param root string
---@param file string
---@return string?
function M.module_for(root, file)
  if not file or file == "" then
    return nil
  end
  local rel = vim.fs.relpath(root, file)
  if not rel or rel:match "^%.%." then
    return nil
  end
  rel = rel:gsub("\\", "/")
  rel = rel:gsub("^src/", "")
  rel = rel:gsub("%.py$", "")
  rel = rel:gsub("/__init__$", ""):gsub("^__init__$", "")
  rel = rel:gsub("/__main__$", ""):gsub("^__main__$", "")
  if rel == "" then
    return ""
  end
  for part in rel:gmatch "[^/]+" do
    if not part:match "^[%a_][%w_]*$" then
      return nil
    end
  end
  return (rel:gsub("/", "."))
end

---@param dir string
---@return fun(): string?, string?
local function entries(dir)
  if not vim.uv.fs_stat(dir) then
    return function()
      return nil
    end
  end
  return vim.fs.dir(dir)
end

--- Packages with a __main__.py: src/<pkg>/__main__.py and <pkg>/__main__.py (plus a root __main__.py)
---@param root string
---@return { module: string, path: string }[]
local function main_modules(root)
  local out = {}
  local function scan(dir)
    for name, kind in entries(dir) do
      if kind == "directory" and not SKIP_DIRS[name] and name ~= "src" and name:match "^[%a_][%w_]*$" then
        local path = dir .. "/" .. name .. "/__main__.py"
        if vim.uv.fs_stat(path) then
          out[#out + 1] = { module = name, path = path }
        end
      end
    end
  end
  scan(root .. "/src")
  scan(root)
  if vim.uv.fs_stat(root .. "/__main__.py") then
    out[#out + 1] = { module = "", path = root .. "/__main__.py" }
  end
  return out
end

--- How the project can be started, best first: console scripts, packages with __main__.py, Django, main.py /
--- app.py / run.py (FastAPI, Flask, Streamlit or a plain script).
---@param root string
---@return { label: string, desc: string, cmd: string, value: string, path: string? }[]
function M.entrypoints(root)
  local out, seen = {}, {}
  local py = M.python(root)
  local is_uv = vim.fn.executable "uv" == 1 and M.uv_project(root)

  local function rel(path)
    local r = vim.fs.relpath(root, path)
    return r and r:gsub("\\", "/") or path
  end

  local function add(label, desc, cmd, path)
    if cmd == "" or seen[cmd] then
      return
    end
    seen[cmd] = true
    out[#out + 1] = { label = label, desc = desc, cmd = cmd, value = cmd, path = path }
  end

  for _, script in ipairs(M.scripts(root)) do
    local cmd
    if is_uv then
      cmd = "uv run " .. vim.fn.shellescape(script.name)
    else
      local module, func = script.target:match "^([^:]+):?(.*)$"
      if func and func ~= "" then
        cmd = py .. " -c " .. vim.fn.shellescape(("from %s import %s; %s()"):format(module, func, func))
      else
        cmd = py .. " -m " .. module
      end
    end
    add(script.name, script.target, cmd)
  end

  for _, main in ipairs(main_modules(root)) do
    add(
      main.module ~= "" and ("module " .. main.module) or "package",
      rel(main.path),
      main.module ~= "" and (py .. " -m " .. main.module) or (py .. " " .. vim.fn.shellescape(root)),
      main.path
    )
  end

  local manage = root .. "/manage.py"
  if vim.uv.fs_stat(manage) then
    add("Django dev server", rel(manage), py .. " manage.py runserver", manage)
  end

  for _, name in ipairs { "main.py", "app.py", "run.py" } do
    local path = root .. "/" .. name
    if vim.uv.fs_stat(path) then
      local text = M.read(path) or ""
      local module = M.module_for(root, path)
      local fastapi = text:match "([%a_][%w_]*)[%s]*=[%s]*FastAPI%s*%("
      local flask = text:match "([%a_][%w_]*)[%s]*=[%s]*Flask%s*%("
      if fastapi and module then
        add(
          "FastAPI dev server",
          rel(path),
          (is_uv and "uv run " or "") .. "uvicorn " .. module .. ":" .. fastapi .. " --reload",
          path
        )
      elseif flask and module then
        add(
          "Flask dev server",
          rel(path),
          (is_uv and "uv run " or "") .. "flask --app " .. module .. ":" .. flask .. " run --debug",
          path
        )
      elseif text:find("import streamlit", 1, true) or text:find("from streamlit", 1, true) then
        add(
          "Streamlit app",
          rel(path),
          (is_uv and "uv run " or "") .. "streamlit run " .. vim.fn.shellescape(path),
          path
        )
      else
        add(name, rel(path), py .. " " .. vim.fn.shellescape(path), path)
      end
    end
  end

  return out
end

--- Files worth opening in a Python project (only the ones that exist)
---@param root string
---@return { label: string, desc: string, value: string, path: string }[]
function M.project_files(root)
  local out = {}
  for _, file in ipairs(PROJECT_FILES) do
    local path = root .. "/" .. file[1]
    if vim.uv.fs_stat(path) then
      out[#out + 1] = { label = file[1], desc = file[2], value = path, path = path }
    end
  end
  return out
end

return M
