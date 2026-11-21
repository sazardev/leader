-- ── Python actions ───────────────────────────────────────────────────────────
-- Runs through uv when the project is a uv project (uv.lock), else the project's .venv, else python3. Run the file,
-- the project (detected entry point) or the file as a module; REPL / floating IPython (with send line/selection) /
-- JupyterLab; uv add, add --dev, remove,
-- sync, lock upgrade, tree, outdated and build; ruff check / fix / format / imports; basedpyright typecheck; tests in
-- the editor (langtest), debugging with debugpy (langdebug), setup files under `S` and the uv project under `P`.
local actions = require "utils.actions"
local log = require "utils.log"
local py = require "utils.python"
local terminal = require "utils.terminal"

---@return string
local function root()
  return py.root()
end

--- uv only in a uv project (its lockfile is there) and when uv is installed
---@return boolean
local function uv()
  return vim.fn.executable "uv" == 1 and py.uv_project(root())
end

--- The interpreter of the project: uv run, the .venv's python, python3
---@return string
local function python()
  return py.python(root())
end

local function current_file()
  return vim.fn.shellescape(vim.fn.expand "%:p")
end

--- The terminal runs the file on disk, not the unsaved buffer: save it first
---@return boolean
local function ensure_saved()
  if vim.api.nvim_buf_get_name(0) == "" or not vim.bo.modified then
    return true
  end
  local ok, err = pcall(vim.cmd, "write")
  if not ok then
    log.warn("Python: could not save the buffer: " .. tostring(err))
    return false
  end
  return true
end

--- A uv command, or a note when uv or the project is missing
local function uv_cmd(sub, ask)
  return function()
    if vim.fn.executable "uv" ~= 1 then
      return log.warn "Python: uv is not installed (curl -LsSf https://astral.sh/uv/install.sh | sh)"
    end
    if not py.has_pyproject(root()) then
      return log.warn "Python: no pyproject.toml (uv needs a project; <leader>pPi creates one)"
    end
    if not ask then
      return terminal.run("uv " .. sub, root())
    end
    require("utils.modal").input({ ask }, { title = "uv " .. sub, confirm = "Run" }, function(text)
      if text ~= "" then
        terminal.run(("uv %s %s"):format(sub, text), root())
      end
    end)
  end
end

--- A binary on PATH, else Mason's bin
---@param name string
---@return string?
local function executable(name)
  local path = vim.fn.exepath(name)
  if path ~= "" then
    return path
  end
  local mason = vim.fn.stdpath "data" .. "/mason/bin/" .. name
  if vim.fn.executable(mason) == 1 then
    return mason
  end
end

--- The project's entry point: one runs directly, several open a picker
local function run_project()
  if not ensure_saved() then
    return
  end
  local r = root()
  local items = py.entrypoints(r)
  local file = vim.api.nvim_buf_get_name(0)
  if #items == 0 and file ~= "" then
    items = {
      {
        label = vim.fs.basename(file),
        desc = "current file",
        value = python() .. " " .. current_file(),
        cmd = python() .. " " .. current_file(),
      },
    }
  end
  if #items == 0 then
    return log.warn "Python: no entry point found (pyproject [project.scripts], __main__.py, main.py, app.py)"
  end
  if #items == 1 then
    return terminal.run(items[1].value, r)
  end
  require("tasks.picker").choose(items, { title = "Run project", hint = "Enter run" }, function(item)
    terminal.run(item.value, r)
  end)
end

--- Run the file: a PEP 723 script goes through `uv run` (its inline dependencies); anything else through the project's
--- interpreter.
local function run_file()
  if vim.api.nvim_buf_get_name(0) == "" then
    return log.warn "Python: save the buffer first"
  end
  if not ensure_saved() then
    return
  end
  local head = table.concat(vim.api.nvim_buf_get_lines(0, 0, 20, false), "\n")
  if vim.fn.executable "uv" == 1 and py.is_script(head) then
    return terminal.run("uv run " .. current_file(), root())
  end
  terminal.run(python() .. " " .. current_file(), root())
end

--- `python -m <package.module>`: the same file, but with the package's relative imports working
local function run_module()
  if not ensure_saved() then
    return
  end
  local r = root()
  local module = py.module_for(r, vim.api.nvim_buf_get_name(0))
  if not module then
    return log.warn "Python: this file is not a module inside the project (folder names must be identifiers)"
  end
  terminal.run(python() .. (module == "" and " ." or (" -m " .. module)), r)
end

--- The IPython command for this project (uv first, then a global install)
---@return string?
local function ipython_base()
  if uv() then
    return "uv run ipython"
  end
  if vim.fn.executable "ipython" == 1 then
    return "ipython"
  end
end

--- The efficient REPL flags: no banner, no confirmation, history suggestions on
---@return string?
local function ipython_repl()
  local base = ipython_base()
  if not base then
    return nil
  end
  return base
    .. " --no-banner --no-confirm-exit"
    .. " --TerminalInteractiveShell.autosuggestions_provider=NavigableAutoSuggestFromHistory"
end

local function ipython()
  if not ensure_saved() then
    return
  end
  local cmd = ipython_base()
  if not cmd then
    return log.warn "Python: IPython is not installed (uv add --dev ipython)"
  end
  if vim.api.nvim_buf_get_name(0) ~= "" then
    cmd = cmd .. " -i " .. current_file()
  end
  terminal.run(cmd, root())
end

--- Floating, persistent IPython: <leader>pF toggles it, Esc hides it and the process survives.
local function floating_ipython()
  local cmd = ipython_repl()
  if not cmd then
    return log.warn "Python: IPython is not installed (uv add --dev ipython)"
  end
  terminal.float_repl("Python REPL", cmd, root())
end

--- Current line, or the selected lines in visual mode.
---@return string[]
local function selected_lines()
  local mode = vim.fn.mode()
  local first, last
  if mode:match "[vV\22]" then
    first, last = vim.fn.getpos("v")[2], vim.fn.getpos(".")[2]
    if first > last then
      first, last = last, first
    end
    vim.cmd "normal! \27"
  else
    first, last = vim.fn.line ".", vim.fn.line "."
  end
  return vim.api.nvim_buf_get_lines(0, first - 1, last, false)
end

--- Send the line or visual selection to the floating REPL. Multi-line blocks go
--- as one bracketed paste (keeping indentation); a single line goes directly.
local function send_ipython()
  local cmd = ipython_repl()
  if not cmd then
    return log.warn "Python: IPython is not installed (uv add --dev ipython)"
  end
  local lines = selected_lines()
  if #lines == 0 or (#lines == 1 and lines[1]:match "^%s*$") then
    return
  end
  local text = table.concat(lines, "\n")
  local block = #lines > 1 or lines[1]:match "^%s+" ~= nil or text:match ":%s*$" ~= nil
  terminal.send_text("Python REPL", cmd, root(), text, block)
  log.info(("Python: sent %s to IPython"):format(#lines == 1 and "line" or (#lines .. " lines")))
end

local function jupyter()
  local r = root()
  local cmd
  if uv() then
    cmd = "uv run jupyter lab"
  elseif vim.fn.executable "jupyter" == 1 then
    cmd = "jupyter lab"
  else
    return log.warn "Python: JupyterLab is not installed (uv add --dev jupyterlab)"
  end
  terminal.run(cmd, r)
end

local function build()
  if vim.fn.executable "uv" ~= 1 then
    return log.warn "Python: uv is not installed"
  end
  if not py.has_pyproject(root()) then
    return log.warn "Python: no pyproject.toml to build"
  end
  terminal.run("uv build", root())
end

local function typecheck()
  local bin = executable "basedpyright" or executable "pyright"
  if not bin then
    return log.warn "Python: basedpyright is not installed (:MasonInstall basedpyright)"
  end
  local r = root()
  local args = { vim.fn.shellescape(bin) }
  local venv = py.venv_python(r)
  if venv then
    vim.list_extend(args, { "--pythonpath", vim.fn.shellescape(venv) })
  end
  args[#args + 1] = "."
  terminal.run(table.concat(args, " "), r)
end

--- Quote every package spec, so `pandas<3` reaches uv instead of the shell's redirection
---@param list string[]
---@return string
local function shell_args(list)
  local out = {}
  for _, item in ipairs(list) do
    out[#out + 1] = vim.fn.shellescape(item)
  end
  return table.concat(out, " ")
end

---@param text string
---@return string
local function absolute(text)
  local path = vim.fn.expand(text)
  if not path:match "^/" and not path:match "^%a:[/\\]" and not path:match "^\\\\" then
    path = vim.fn.getcwd() .. "/" .. path
  end
  return (vim.fn.fnamemodify(path, ":p"):gsub("[/\\]+$", ""))
end

--- New uv project: application, library, script or data analysis (uv init). Applications and libraries sync;
--- data analysis installs the full stack with pandas 2.x (the 2022 book's era).
local function init_project()
  local kinds = {
    {
      label = "Application",
      desc = "src/<name>/ + console script + .venv",
      value = { flag = "app", default = "my-project" },
    },
    {
      label = "Library",
      desc = "src/<name>/ + pyproject.toml",
      value = { flag = "lib", default = "my-library" },
    },
    {
      label = "Script",
      desc = "one file with PEP 723 metadata",
      value = { flag = "script", default = "script.py" },
    },
    {
      label = "Data analysis",
      desc = "pandas 2.x (book) + NumPy, JupyterLab, SciPy, statsmodels, scikit-learn",
      value = { flag = "data", default = "my-data-project" },
    },
  }
  require("tasks.picker").choose(kinds, { title = "New uv project", hint = "Enter choose" }, function(kind)
    local modal = require "utils.modal"
    modal.input({
      "Create a uv project",
      { { "Kind: ", modal.hl.muted }, { kind.label } },
    }, { title = "uv init", confirm = "Create", default = kind.default }, function(text)
      if text == "" then
        return
      end
      if kind.flag == "script" and not text:match "%.py$" then
        text = text .. ".py"
      end
      local path = absolute(text)
      local name = vim.fs.basename(path)
      local parent = vim.fs.dirname(path)
      local cmd
      if kind.flag == "script" then
        cmd = ("uv init --script %s"):format(vim.fn.shellescape(path))
      elseif kind.flag == "data" then
        cmd = ("uv init --bare --name %s %s && cd %s && uv add %s && uv add --dev %s"):format(
          vim.fn.shellescape(name),
          vim.fn.shellescape(path),
          vim.fn.shellescape(path),
          shell_args(py.DATA.runtime),
          shell_args(py.DATA.dev)
        )
      else
        cmd = ("uv init --%s --name %s %s && cd %s && uv sync"):format(
          kind.flag,
          vim.fn.shellescape(name),
          vim.fn.shellescape(path),
          vim.fn.shellescape(path)
        )
      end
      terminal.run(cmd, parent)
      log.info(("Python: creating %s%s"):format(path, kind.flag == "data" and " with the data stack" or ""))
    end)
  end)
end

local function create_venv()
  local r = root()
  local modal = require "utils.modal"
  local version = py.python_version(r) or "3.14"
  local function create(clear)
    modal.input({
      "Create the virtual environment",
      { { "Python: ", modal.hl.muted }, { version } },
    }, { title = "uv venv", confirm = clear and "Recreate" or "Create", default = version }, function(text)
      if text == "" then
        return
      end
      local cmd
      if vim.fn.executable "uv" == 1 then
        cmd = ("uv venv %s--python %s .venv"):format(clear and "--clear " or "", vim.fn.shellescape(text))
      else
        cmd = ("python3 -m venv %s.venv"):format(clear and "--clear " or "")
      end
      terminal.run(cmd, r)
    end)
  end
  if vim.uv.fs_stat(r .. "/.venv") then
    modal.confirm({
      "`.venv` already exists.",
      "Recreating it deletes the packages installed in it.",
    }, { title = "uv venv", confirm = "Recreate", danger = true }, function()
      create(true)
    end)
  else
    create(false)
  end
end

local function pin_python()
  if vim.fn.executable "uv" ~= 1 then
    return log.warn "Python: uv is not installed"
  end
  local modal = require "utils.modal"
  local version = py.python_version(root()) or "3.14"
  modal.input({
    "Install and pin the project's Python",
    { { "Version: ", modal.hl.muted }, { version } },
  }, { title = "uv python pin", confirm = "Pin", default = version }, function(text)
    if text == "" then
      return
    end
    terminal.run(
      ("uv python install %s && uv python pin %s"):format(vim.fn.shellescape(text), vim.fn.shellescape(text)),
      root()
    )
  end)
end

local function uv_run()
  if vim.fn.executable "uv" ~= 1 then
    return log.warn "Python: uv is not installed"
  end
  if not py.has_pyproject(root()) then
    return log.warn "Python: no pyproject.toml (uv run needs a project; <leader>pPi creates one)"
  end
  require("utils.modal").input({
    "Command to run in the project environment (uv run)",
  }, { title = "uv run", confirm = "Run" }, function(text)
    if text == "" then
      return
    end
    terminal.run("uv run " .. text, root())
  end)
end

local function uvx()
  if vim.fn.executable "uv" ~= 1 then
    return log.warn "Python: uv is not installed"
  end
  require("utils.modal").input({
    "Tool to run with uvx (e.g. ruff check .)",
  }, { title = "uvx", confirm = "Run" }, function(text)
    if text == "" then
      return
    end
    terminal.run("uvx " .. text, root())
  end)
end

local function project_files()
  local r = root()
  local items = py.project_files(r)
  if #items == 0 then
    return log.warn "Python: no project file found (pyproject.toml, uv.lock, ...)"
  end
  require("tasks.picker").choose(items, { title = "Python project files", preview = true }, function(path)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  end)
end

--- Check the editor-side Python toolchain and install what Leader can install: uv and the Mason tools
local function doctor()
  local modal = require "utils.modal"
  local ok, registry = pcall(require, "mason-registry")
  local missing = {}
  if ok then
    for _, name in ipairs(py.TOOLS) do
      if not registry.is_installed(name) then
        missing[#missing + 1] = name
      end
    end
  end
  local has_python = vim.fn.executable "python3" == 1
  local has_uv = vim.fn.executable "uv" == 1
  local lines = {
    "Python toolchain",
    { { "python3: ", modal.hl.muted }, { has_python and "installed" or "missing (install Python 3)" } },
    { { "uv: ", modal.hl.muted }, { has_uv and "installed" or "missing (projects, packages, uv run)" } },
    {
      { "Mason: ", modal.hl.muted },
      {
        #missing == 0 and (table.concat(py.TOOLS, ", ") .. " installed") or ("missing " .. table.concat(missing, ", ")),
      },
    },
  }
  if has_python and has_uv and #missing == 0 then
    return log.info "Python: uv, ruff, basedpyright and debugpy are ready"
  end
  if not has_python and #missing > 0 then
    return log.warn "Python: Python 3 is missing; install it with your package manager or the setup wizard first"
  end
  if not has_python and has_uv then
    return log.warn "Python: Python 3 is missing; install it with your package manager (or `uv python install 3.14`)"
  end
  modal.confirm(lines, { title = "Python doctor", confirm = "Install missing" }, function()
    if not has_uv then
      local bin = vim.fn.expand "~/.local/bin"
      local sep = vim.fn.has "win32" == 1 and ";" or ":"
      if not (vim.env.PATH or ""):find(bin, 1, true) then
        vim.env.PATH = bin .. sep .. (vim.env.PATH or "")
      end
      local cmd
      if vim.fn.has "win32" == 1 then
        cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://astral.sh/uv/install.ps1 | iex"'
      else
        cmd = "curl -LsSf https://astral.sh/uv/install.sh | sh"
      end
      terminal.run(cmd, vim.fn.expand "~")
      log.info "Python: uv installer started; open a new terminal or restart Leader when it finishes"
    end
    if #missing > 0 then
      vim.cmd("MasonInstall " .. table.concat(missing, " "))
    end
  end)
end

--- Inlay hints: basedpyright's call-argument names and return types, on by default
local function inlay_hints()
  local buf = vim.api.nvim_get_current_buf()
  local enabled = vim.lsp.inlay_hint.is_enabled { bufnr = buf }
  vim.lsp.inlay_hint.enable(not enabled, { bufnr = buf })
  log.info("Python: inlay hints " .. (enabled and "off" or "on"))
end

local maps = {
  { "r", "run file", run_file },
  { "p", "run project (entry point)", run_project },
  { "l", "run as module (-m)", run_module },
  {
    "i",
    "REPL with the file",
    function()
      terminal.run(python() .. " -i " .. current_file(), root())
    end,
  },
  { "I", "IPython with the file", ipython },
  { "F", "floating IPython REPL", floating_ipython },
  { "s", "send line/selection to IPython", send_ipython, { "n", "x" } },
  { "j", "JupyterLab", jupyter },
  { "b", "build (uv build)", build },
  { "a", "uv add package", uv_cmd("add", "Packages to add (e.g. httpx pydantic, --dev pytest)") },
  { "d", "uv add --dev package", uv_cmd("add --dev", "Dev packages to add (e.g. pytest ruff)") },
  { "R", "uv remove package", uv_cmd("remove", "Packages to remove") },
  { "u", "uv sync", uv_cmd "sync" },
  { "U", "uv lock upgrade", uv_cmd "lock --upgrade" },
  { "t", "dependency tree (uv tree)", uv_cmd "tree" },
  {
    "v",
    "ruff check",
    actions.run("ruff", "ruff check .", py.MARKERS),
  },
  { "x", "ruff fix", actions.run("ruff", "ruff check --fix .", py.MARKERS) },
  { "f", "format", actions.format },
  { "o", "organize imports", actions.code_action "source.organizeImports.ruff" },
  { "y", "typecheck (basedpyright)", typecheck },
  {
    "c",
    "coverage",
    function()
      terminal.run(python() .. " -m pytest --cov --cov-report=term-missing", root())
    end,
  },
  {
    "e",
    "interpreter in use",
    function()
      terminal.run(python() .. " -c 'import sys; print(sys.executable); print(sys.version)'", root())
    end,
  },
  { "h", "toggle inlay hints", inlay_hints },
  { "Pi", "init a uv project", init_project },
  { "Pv", "create virtual environment", create_venv },
  { "Pp", "install and pin Python", pin_python },
  { "Pr", "run a command (uv run)", uv_run },
  { "Po", "outdated dependencies", uv_cmd "tree --outdated" },
  { "Px", "run a tool (uvx)", uvx },
  { "Pf", "project files", project_files },
  { "Pk", "check tools (install missing)", doctor },
}

vim.api.nvim_create_user_command("PythonInit", init_project, {
  desc = "Python: create a uv project (application, library, script or data analysis)",
  force = true,
})
vim.api.nvim_create_user_command("PythonDoctor", doctor, {
  desc = "Python: check/install uv, ruff, basedpyright and debugpy",
  force = true,
})

vim.list_extend(maps, require("langtest").maps())
vim.list_extend(maps, require("langdebug").maps "python")
vim.list_extend(maps, require("langsetup").maps "python")
return maps
