# Markdown

Filetype: `markdown` (`*.md` and `*.mdx` — MDX is detected as `markdown`, see `ftdetect/mdx.lua`).

## Tools

| What | With |
|---|---|
| Format (on save and `<leader>fm`) | `markdownlint-cli2` (fixes rules) and then `prettier` |
| Lint | `markdownlint` |
| Render | `render-markdown.nvim` (styled headings, lists, code, checkboxes) |
| Treesitter | `markdown` |

## `<leader>m` menu (only in `*.md` and `*.mdx`)

MDX (`*.mdx`) is tolerant: no `mdx` parser exists in `nvim-treesitter`, so it reuses Markdown rendering, formatting and linting — JSX shows as HTML, `tsx`/`jsx` fences highlight, and imports/expressions stay as text instead of erroring.

The keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md) (generated; not duplicated here).

- Opening `*.md`/`*.mdx` enters the **locked reading mode** (`modifiable=false`, centered 80 columns, no numbers/diagnostics): clicks and edits do nothing until `Esc` leaves it (also `<leader>mz` toggles it).
- The diagnostics toggle hides the linter's diagnostics **only in this buffer** (the linter keeps running).
- With spell checking on (es, en): `]s` / `[s` jump between errors and `z=` suggests corrections (native Vim).
