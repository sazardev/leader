# Markdown

Filetype: `markdown`.

## Herramientas

| Qué | Con |
|---|---|
| Formato (al guardar y `<leader>fm`) | `markdownlint-cli2` (corrige reglas) y luego `prettier` |
| Lint | `markdownlint` |
| Render | `render-markdown.nvim` (títulos, listas, código, checkboxes con estilo) |
| Treesitter | `markdown` |

## Menú `<leader>m` (solo en `*.md`)

Las teclas están en [`CHEATSHEET.md`](../../CHEATSHEET.md) (generado; no se duplican aquí).

- El toggle de diagnósticos oculta los del linter **solo en este buffer** (el linter sigue corriendo).
- Con la ortografía activa (es, en): `]s` / `[s` saltan entre errores y `z=` sugiere correcciones (nativos de Vim).
