# TypeScript / JavaScript

Filetypes: `typescript`, `typescriptreact`, `javascript`, `javascriptreact`.

## Herramientas

| Qué | Con |
|---|---|
| LSP | `vtsls` (TS/JS) y `eslint` (eslint-lsp) |
| Formato (al guardar y `<leader>fm`) | `prettier` |
| Lint | `eslint_d` |
| Extra | treesitter (`javascript`, `typescript`, `tsx`), `nvim-ts-autotag` (cierra/renombra tags JSX), `package-info` (versiones en `package.json`), preview de colores Tailwind |

## Menú `<leader>t` (solo en ts/tsx/js/jsx)

Las teclas están en [`CHEATSHEET.md`](../../CHEATSHEET.md) (generado; no se duplican aquí).

El gestor de paquetes se detecta por lockfile: `pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `bun.lock(b)` → bun, si no npm.
Usa los scripts de `package.json` cuando existen.

## Notas

- Los scripts corren en la terminal integrada, en la raíz del proyecto (donde está `package.json`).
- `npx --no-install`: no descarga nada; usa lo que ya está en `node_modules`.
