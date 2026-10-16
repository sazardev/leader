<!-- name: Bun workspaces -->
<!-- desc: TypeScript monorepo on Bun workspaces: apps/ and packages/, shared tsconfig, bun test, optional Turborepo -->

# STACK.md: Bun workspaces

## Summary

A TypeScript monorepo managed by Bun workspaces: deployable apps in `apps/`, shared libraries in `packages/`, one lockfile,
one install. Bun runs scripts, tests and TypeScript directly, so most packages need no build step; Turborepo can be added
later for caching when builds get slow. Packages expose a small public API and depend in one direction.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript 7 (strict, project references or path-free imports) | Shared types across packages |
| Runtime / package manager | Bun 1.3+ (workspaces, `bun.lock`) | One fast tool for install, run, test |
| Apps | e.g. a Hono API (`apps/api`) and a Vite web app (`apps/web`) | Any TS app |
| Shared | `packages/domain`, `packages/ui`, `packages/config` | Reuse without copy-paste |
| Testing | `bun test` | Built in, fast |
| Lint | Biome (one config at the root) | One fast tool |
| Task caching | Turborepo (optional) | Add when builds are slow |

## Project layout

```
package.json                 "workspaces": ["apps/*", "packages/*"], root scripts
bun.lock
biome.json
tsconfig.base.json
apps/
  api/
    package.json             "dependencies": { "@acme/domain": "workspace:*" }
    src/index.ts
  web/
    package.json
    src/main.ts
packages/
  domain/
    package.json             "exports": { ".": "./src/index.ts" }
    src/index.ts             public API only
    src/invoice.ts
    src/invoice.test.ts
  ui/
  config/                    shared tsconfig/biome presets
```

Dependency direction: `apps → packages`; packages never import apps; `domain` depends on nothing else in the repo.

## Conventions

- Internal packages named `@acme/<name>`, depended on with `workspace:*`.
- Each package exports only through `src/index.ts`; deep imports are not allowed.
- Root scripts fan out with `bun --filter '*' <script>`.

## Commands

| Task | Command |
| --- | --- |
| Install | `bun install` |
| Dev (api) | `bun --filter @acme/api dev` |
| Test all | `bun test` |
| Typecheck | `bun --filter '*' typecheck` |
| Lint | `bunx biome check .` |
| Build all | `bun --filter '*' build` |

## Testing

- Tests next to code (`*.test.ts`) in every package; `bun test` at the root runs them all.

## Quality gates

- Biome, typecheck in every package and `bun test` green; no package imports another's internals.

## Dependencies

- Shared versions decided at the root; a dependency used by one package lives in that package.
- Do NOT use: relative imports across packages (`../../packages/x/src`), multiple lockfiles, publishing internal packages without need.

## Rules for agents

- Add internal dependencies with `workspace:*` and run `bun install` at the root.
- Import packages by name, never by relative path across package boundaries.
- Keep each package's public API in `src/index.ts`.
- New shared code goes to an existing package before creating a new one.
- Run `bun test` and the typecheck for every package you touched.
- Keep app-specific code out of `packages/`.
- One `biome.json` at the root; do not add per-package lint configs.
- Avoid circular dependencies between packages.
