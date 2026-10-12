# Python

Filetype: `python`.

## Herramientas

| Qué | Con |
|---|---|
| Treesitter | `python` |
| LSP / formatter / linter | **no hay declarados** en el registro (solo menú + treesitter); el formato/lint se hace con `ruff` desde el menú |

> Si quieres LSP o formato automático al guardar, se añade en `lua/languages/python.lua` (campos `lsp`, `mason`, `formatters`, `linters`) sin tocar nada más.

## Menú `<leader>p` (solo en `*.py`)

Las teclas están en [`CHEATSHEET.md`](../../CHEATSHEET.md) (generado; no se duplican aquí).

Usa `uv run` si `uv` está instalado y el proyecto tiene `pyproject.toml`; si no, `python3`.
Raíz del proyecto: donde esté `pyproject.toml`, `pytest.ini`, `setup.cfg` o `.git`.
Las acciones de ruff avisan si `ruff` no está instalado.
