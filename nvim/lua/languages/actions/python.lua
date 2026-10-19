-- ── Python actions ───────────────────────────────────────────────────────────
-- Runs through uv when the project is a uv project (uv.lock), else the project's .venv, else python3. Tests run in the
-- editor (langtest: marks, failures as diagnostics), debugging with debugpy (langdebug), setup files under `S`.
local actions = require "utils.actions"
local log = require "utils.log"
local project = require "utils.project"
local terminal = require "utils.terminal"

local MARKERS = { "pyproject.toml", "pytest.ini", "setup.cfg", "requirements.txt", ".git" }

---@return string
local function root()
  return project.root(MARKERS)
end

--- uv only in a uv project (its lockfile is there) and when uv is installed
---@return boolean
local function uv()
  return vim.fn.executable "uv" == 1 and vim.uv.fs_stat(root() .. "/uv.lock") ~= nil
end

--- The interpreter of the project: uv run, the .venv's python, python3
---@return string
local function python()
  if uv() then
    return "uv run python"
  end
  for _, p in ipairs { "/.venv/bin/python", "/venv/bin/python" } do
    if vim.fn.executable(root() .. p) == 1 then
      return vim.fn.shellescape(root() .. p)
    end
  end
  return "python3"
end

local function current_file()
  return vim.fn.shellescape(vim.fn.expand "%:p")
end

--- A uv command, or a note when the project does not use uv
local function uv_cmd(sub, ask)
  return function()
    if vim.fn.executable "uv" ~= 1 then
      return log.warn "Python: uv is not installed (curl -LsSf https://astral.sh/uv/install.sh | sh)"
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

local maps = {
  {
    "r",
    "run file",
    function()
      terminal.run(python() .. " " .. current_file(), root())
    end,
  },
  {
    "i",
    "REPL with the file",
    function()
      terminal.run(python() .. " -i " .. current_file(), root())
    end,
  },
  { "v", "ruff check", actions.run("ruff", "ruff check .", MARKERS) },
  { "x", "ruff fix", actions.run("ruff", "ruff check --fix .", MARKERS) },
  { "f", "format", actions.format },
  { "o", "organize imports", actions.code_action "source.organizeImports.ruff" },
  { "a", "uv add package", uv_cmd("add", "Packages to add (e.g. httpx pydantic, --dev pytest)") },
  { "u", "uv sync", uv_cmd "sync" },
  { "U", "uv lock upgrade", uv_cmd "lock --upgrade" },
  { "R", "uv remove package", uv_cmd("remove", "Packages to remove") },
  {
    "c",
    "coverage",
    function()
      terminal.run((uv() and "uv run " or "") .. "pytest --cov --cov-report=term-missing", root())
    end,
  },
  {
    "e",
    "interpreter in use",
    function()
      terminal.run(python() .. " -c 'import sys; print(sys.executable); print(sys.version)'", root())
    end,
  },
}

vim.list_extend(maps, require("langtest").maps())
vim.list_extend(maps, require("langdebug").maps "python")
vim.list_extend(maps, require("langsetup").maps "python")
return maps
