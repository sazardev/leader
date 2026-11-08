# Web: HTML, CSS, Tailwind, Astro

## HTML
| What | With |
|---|---|
| LSP | `html` and `emmet_ls` (expands Emmet abbreviations: `ul>li*3` + completion) |
| Format (on save and `<leader>fm`) | `prettier` |
| Extra | `nvim-ts-autotag`: typing `<div>` closes `</div>` and renames its pair |

## CSS / SCSS / Less
| What | With |
|---|---|
| LSP | `cssls` |
| Format | `prettier` |
| Color preview | nvim-highlight-colors (hex, rgb, Tailwind) |

### `<leader>s` menu (only in css, scss, less)
The keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md) (generated; not duplicated here).

## Tailwind
- `tailwindcss` server (cross-cutting: it has no filetype of its own, it applies wherever the project uses Tailwind).
- Class completion, and Tailwind color preview in the buffer.

## Astro
| What | With |
|---|---|
| LSP | `astro-language-server` |
| Format | `prettier` — **requires `prettier-plugin-astro`** in the project (`node_modules`) or installed globally; Mason only installs `prettier` |

### `<leader>o` menu (only in `astro`)

The keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md) (generated; not duplicated here) — `dev` / `build` / `preview` and **Setup**
(`<leader>oS`): `astro.config.mjs`, `tsconfig.json` (Astro strict), Prettier, `.editorconfig`, Node `Dockerfile` and its `.dockerignore`,
GitHub Actions and `.nvmrc`. Presets live in `lua/langsetup/presets/astro/` and are filled from `package.json` and the lockfile.

### Docker / Prisma (generic project setup)

- **Docker** (`<leader>DS`, in `dockerfile` buffers): `Dockerfile`, `compose.yaml`, `.dockerignore`, `.hadolint.yaml`, `.editorconfig`.
- **Prisma** (`<leader>eS`, in `prisma` buffers): `prisma/schema.prisma` (PostgreSQL by default, from the existing schema's provider),
  `compose.yaml` for the database, `.editorconfig`, GitHub Actions (`prisma validate` + `generate`).
