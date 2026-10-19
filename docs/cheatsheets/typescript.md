# TypeScript / JavaScript

Filetypes: `typescript`, `typescriptreact`, `javascript`, `javascriptreact`. Pack `typescript`.

## Tools

| What | With |
|---|---|
| LSP | `vtsls` (TS/JS), `eslint` (where the project has an eslint config), `biome` (where it has a `biome.json`) |
| Format on save | **biome** where the project has a `biome.json`, **prettier** everywhere else |
| Lint | `eslint_d` |
| Extra | treesitter (`javascript`, `typescript`, `tsx`, `jsdoc`), `nvim-ts-autotag`, `package-info` (versions in `package.json`), Tailwind color preview |

The package manager comes from the lockfile: `pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `bun.lock(b)` → bun,
otherwise npm. The project's own binaries run with its exec (`pnpm exec`, `yarn`, `bunx`, `npx --no-install`): nothing
is ever downloaded.

## `<leader>t` menu (only in ts/tsx/js/jsx)

The keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md). What they do:

- **Scripts**: a picker of the `package.json` scripts, `dev`, `build`, `lint` (eslint when there is no script).
- **Typecheck**: `tsc --noEmit` on the whole project, its errors in the quickfix list (no terminal to read).
- **Tests in the editor**: the runner comes from `package.json` (vitest or jest in the dependencies or the `test`
  script, else `bun test` in a bun project). The test under the cursor is the `it`/`test` (or `describe`) around it,
  `.only`/`.skip`/`.each` included, selected by its full name; the file; the project; the last run again. Marks per test
  line, failures as diagnostics on the line the stack trace points at, the quickfix list. The file toggle jumps between
  `x.ts` and `x.test.ts` (or `x.spec.ts` when that is the one there).
- **Code actions** (vtsls): organize imports, add missing imports, fix all; go to the source definition (the `.ts`
  file instead of the `.d.ts`).
- **Packages**: install, add (what you type: `-D vitest`), remove, outdated.
- **Setup** (`<leader>tS`): tsconfig (strict Node/Bun, strict React with a bundler, a library that emits `.d.ts`),
  Biome (recommended or strict), ESLint flat config with typescript-eslint, Prettier, Vitest config (Node or React),
  a Dockerfile (Node multi-stage or Bun) and its `.dockerignore`, GitHub Actions (install, lint, typecheck, test, build
  with the project's package manager), `.nvmrc`, `.editorconfig`, a Makefile preset, `.gitignore`.

## Snippets

`describetest`, `ittest`, `zodschema` (with its type), `resulttype`, `asyncfunction`, `exhaustive` (a switch the
compiler checks); in TSX also `component` (typed props) and `usehook`.

## Notes

- Biome and Prettier never both format: Biome only runs where a `biome.json` is.
- `npx --no-install` fails when the tool is not in `node_modules`: install it in the project first.
