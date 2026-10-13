# Python

Filetype: `python`.

## Tools

| What | With |
|---|---|
| Treesitter | `python` |
| LSP / formatter / linter | **none declared** in the registry (menu + treesitter only); format/lint is done with `ruff` from the menu |

> If you want LSP or automatic format on save, add it in `lua/languages/python.lua` (fields `lsp`, `mason`, `formatters`, `linters`) without touching anything else.

## `<leader>p` menu (only in `*.py`)

The keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md) (generated; not duplicated here).

It uses `uv run` if `uv` is installed and the project has `pyproject.toml`; otherwise `python3`.
Project root: wherever `pyproject.toml`, `pytest.ini`, `setup.cfg` or `.git` is.
The ruff actions warn if `ruff` is not installed.
