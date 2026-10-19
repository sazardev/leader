-- Python: basedpyright for types and navigation, ruff for lint, quick fixes, imports and format (one fast tool, also
-- in light mode, where it runs as a linter instead of a server). The project's .venv is used when there is one
-- (servers/basedpyright.lua). Menu: run, tests in the editor, uv, project setup (languages/actions/python.lua).
return {
  filetypes = { "python" },
  treesitter = { "python", "toml", "requirements" },
  lsp = { "basedpyright", "ruff" },
  mason = {
    always = { "ruff" },
    full = { "basedpyright", "debugpy" },
  },
  formatters = { python = { "ruff_organize_imports", "ruff_format" } },
  linters_light = { python = { "ruff" } }, -- full mode: the ruff server reports the same
  menu = {
    name = "Python",
    prefix = "p",
    maps = require "languages.actions.python",
    groups = { S = "setup", D = "debug" },
  },
}
