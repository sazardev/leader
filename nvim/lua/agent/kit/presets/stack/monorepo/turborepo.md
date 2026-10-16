<!-- name: Turborepo + pnpm -->
<!-- desc: TypeScript monorepo: pnpm workspaces, Turborepo cached pipeline, shared ui/config/domain, changesets -->

# STACK.md: Turborepo + pnpm

## Summary

A TypeScript monorepo with pnpm workspaces and Turborepo. Deployable applications live in `apps/`, reusable code in
`packages/` (UI kit, domain logic, shared configs). Turborepo runs tasks in dependency order and caches their outputs
locally and remotely, so CI only rebuilds what changed. Internal packages are consumed as workspace dependencies
(`workspace:*`); published packages are versioned with changesets.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Package manager | pnpm 9+ with workspaces | Strict, fast, disk-efficient, no phantom deps |
| Task runner | Turborepo (`turbo.json` tasks) | Topological pipeline, local + remote cache |
| Language | TypeScript 7 (native `tsc`, `strict`, project references optional) | One type system across apps |
| Apps | e.g. Next.js (web), Hono/Node (api), Expo (mobile) | Each app picks its framework |
| UI kit | `packages/ui` (React + Tailwind preset or CSS tokens) | One design system |
| Domain | `packages/domain` (pure TS: types, schemas with zod, business rules) | Shared, framework-free |
| Configs | `packages/tsconfig`, `packages/eslint-config`, `packages/tailwind-config` | One source of tooling rules |
| Build libs | `tsup` (or internal packages consumed as TS source) | Simple bundling |
| Testing | Vitest (unit), Playwright (e2e web) | Fast, ESM-native |
| Lint/format | ESLint 9 flat config + Prettier (or Biome) | Shared config package |
| Versioning | changesets | Changelogs and semver for publishable packages |
| Dependency hygiene | `syncpack` or pnpm catalogs, `knip` | Same versions, no unused code |
| CI | GitHub Actions + Turborepo remote cache | Only affected work runs |

## Project layout

```
apps/
  web/                         Next.js app; imports @acme/ui, @acme/domain
  api/                         HTTP API; imports @acme/domain, @acme/db
  mobile/                      Expo app (optional)
packages/
  domain/                      pure TS: entities, zod schemas, use cases; no framework imports
    src/orders/order.ts
    src/orders/place-order.ts
    src/index.ts               explicit public API (exports)
  db/                          DB client + schema (Drizzle/Prisma), only for server apps
  ui/                          components (one per file), tokens, stories
  tsconfig/                    base.json, nextjs.json, library.json
  eslint-config/               base, react, next presets
  tailwind-config/             shared preset (if Tailwind)
turbo.json                     tasks: build, dev, lint, typecheck, test with inputs/outputs
pnpm-workspace.yaml            apps/*, packages/*
.changeset/
```

Dependency direction: `apps → packages`; `ui → domain` allowed, `domain → nothing` (pure). Packages never import from `apps/`; apps never import each other. Each package has a public API (`exports` in `package.json`); no deep imports into `src/`.

## Conventions

- Package names scoped `@acme/<name>`; internal dependencies declared as `"workspace:*"`.
- Every package has `build`, `lint`, `typecheck`, `test` scripts with the same names, so Turborepo can run them everywhere.
- `turbo.json` declares `outputs` for every cached task and `inputs` when defaults are too broad; env vars that affect a build go in `env`.
- One file = one component/module; package `src/index.ts` re-exports only the public API.
- Shared code moves to a package only when two apps need it; no speculative packages.
- Configs (tsconfig, eslint) extend the shared packages; apps do not redefine rules.
- New package = `packages/<name>` with `package.json` (exports, scripts), `tsconfig.json` extending the base, README with its purpose.

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Dev (all) | `pnpm turbo dev` |
| Dev one app | `pnpm turbo dev --filter=web` |
| Build | `pnpm turbo build` |
| Affected only | `pnpm turbo build test --filter=...[origin/main]` |
| Test | `pnpm turbo test` |
| Typecheck | `pnpm turbo typecheck` |
| Lint | `pnpm turbo lint` |
| Format | `pnpm prettier --write .` |
| Add dependency | `pnpm add <pkg> --filter @acme/<name>` |
| Changeset | `pnpm changeset` |
| Unused code | `pnpm knip` |

## Testing

- Each package tests itself with Vitest; `domain` aims for high coverage (pure logic).
- UI components tested with Testing Library; visual review in Storybook (optional).
- Apps keep integration tests next to their routes/handlers and e2e tests (Playwright) for critical flows.
- Tests never import from another package's `src/`; they use its public API.

## Quality gates

- `turbo lint typecheck test build` passes for affected packages on every PR.
- No dependency version drift across packages (`syncpack lint` or pnpm catalogs).
- `knip` reports no unused files, exports or dependencies.
- A change to a publishable package includes a changeset.

## Dependencies

- Add a dependency to the package that uses it, never to the root (root holds only tooling).
- Same version of a library everywhere; upgrades happen in one PR for the whole repo.
- Do NOT use: npm/yarn in parallel with pnpm, `shamefully-hoist`, deep imports (`@acme/ui/src/...`), circular package dependencies, Lerna for task running.

## Rules for agents

- Run tasks through `turbo` with `--filter`; never `cd` into a package and run ad-hoc scripts that bypass the cache.
- Keep `packages/domain` free of React, Node and framework imports.
- Never import from `apps/*` inside a package or from one app into another.
- When adding a task to a package, add or check its `outputs`/`inputs` in `turbo.json`.
- Export new public API through the package's `index.ts`/`exports`; never rely on deep paths.
- Install dependencies with `--filter` on the right package; never edit `pnpm-lock.yaml` by hand.
- Add a changeset when a publishable package changes.
- Prefer extending a shared config over adding local overrides; explain any override in a comment.
