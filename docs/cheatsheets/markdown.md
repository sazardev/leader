# Markdown

Filetype: `markdown`.

## Tools

| What | With |
|---|---|
| Format (on save and `<leader>fm`) | `markdownlint-cli2` (fixes rules) and then `prettier` |
| Lint | `markdownlint` |
| Render | `render-markdown.nvim` (styled headings, lists, code, checkboxes) |
| Treesitter | `markdown` |

## `<leader>m` menu (only in `*.md`)

The keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md) (generated; not duplicated here).

- The diagnostics toggle hides the linter's diagnostics **only in this buffer** (the linter keeps running).
- With spell checking on (es, en): `]s` / `[s` jump between errors and `z=` suggests corrections (native Vim).
