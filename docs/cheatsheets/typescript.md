# TypeScript / JavaScript

Filetypes: `typescript`, `typescriptreact`, `javascript`, `javascriptreact`.

## Tools

| What | With |
|---|---|
| LSP | `vtsls` (TS/JS) and `eslint` (eslint-lsp) |
| Format (on save and `<leader>fm`) | `prettier` |
| Lint | `eslint_d` |
| Extra | treesitter (`javascript`, `typescript`, `tsx`), `nvim-ts-autotag` (closes/renames JSX tags), `package-info` (versions in `package.json`), Tailwind color preview |

## `<leader>t` menu (only in ts/tsx/js/jsx)

The keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md) (generated; not duplicated here).

The package manager is detected by lockfile: `pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `bun.lock(b)` → bun, otherwise npm.
It uses the `package.json` scripts when they exist.

## Notes

- Scripts run in the integrated terminal, at the project root (where `package.json` is).
- `npx --no-install`: downloads nothing; it uses what is already in `node_modules`.
