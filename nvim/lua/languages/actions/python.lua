-- ── Acciones de Python ───────────────────────────────────────────────────────
local actions = require "utils.actions"
local log = require "utils.log"
local project = require "utils.project"
local terminal = require "utils.terminal"

local MARKERS = { "pyproject.toml", "pytest.ini", "setup.cfg", ".git" }

--- `uv` solo si está instalado y el proyecto tiene pyproject.toml
local function use_uv()
  return vim.fn.executable "uv" == 1 and vim.fs.root(0, { "pyproject.toml" }) ~= nil
end

local function current_file()
  return vim.fn.shellescape(vim.fn.expand "%:p")
end

return {
  {
    "r",
    "run file",
    function()
      terminal.run((use_uv() and "uv run " or "python3 ") .. current_file(), project.root(MARKERS))
    end,
  },
  {
    "i",
    "REPL with the file",
    function()
      terminal.run("python3 -i " .. current_file(), project.file_dir())
    end,
  },
  {
    "m",
    "pytest (whole project)",
    function()
      terminal.run(use_uv() and "uv run pytest" or "python3 -m pytest", project.root(MARKERS))
    end,
  },
  {
    "t",
    "pytest (current file)",
    function()
      terminal.run("python3 -m pytest " .. current_file(), project.root(MARKERS))
    end,
  },
  { "v", "ruff check .", actions.run("ruff", "ruff check .", MARKERS) },
  { "x", "ruff check --fix .", actions.run("ruff", "ruff check --fix .", MARKERS) },
  {
    "f",
    "ruff format (current file)",
    function()
      if vim.fn.executable "ruff" ~= 1 then
        return log.warn "`ruff` is not installed"
      end
      vim.cmd "silent write"
      terminal.run("ruff format " .. current_file(), project.file_dir())
    end,
  },
}
