<!-- name: Nx -->
<!-- desc: Nx monorepo: apps + libs by scope/type, module boundaries enforced by tags, generators, affected -->

# STACK.md: Nx

## Summary

A monorepo managed by Nx. Applications are thin; almost all code lives in libraries classified by **scope** (which
domain/app owns it) and **type** (feature, ui, data-access, util). The `@nx/enforce-module-boundaries` lint rule turns
the architecture into a checked rule: a library can only depend on the scopes and types its tags allow. Nx computes the
project graph, runs only affected tasks and caches results locally and remotely.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Workspace | Nx (latest) with plugins (`@nx/js`, `@nx/react`/`@nx/angular`, `@nx/node`, `@nx/vite`) | Graph, caching, generators |
| Package manager | pnpm (or npm) workspaces | Single lockfile |
| Language | TypeScript 7 (native `tsc`) `strict`; keep 6.x if an Nx plugin still needs the TS JS API | Shared types |
| Apps | e.g. React/Next or Angular front-end, Node/Nest API | Plugins exist for each |
| Testing | Vitest or Jest, Playwright/Cypress e2e (`@nx/playwright`) | Per-project targets |
| Lint | ESLint flat config + `@nx/enforce-module-boundaries` | Architecture as lint |
| Format | Prettier (`nx format`) | Uniform |
| Cache | Nx Cloud or self-hosted remote cache | CI reuses results |
| Release | `nx release` (versioning, changelogs, publishing) | Built-in |
| CI | GitHub Actions with `nx affected` (+ distributed execution optional) | Only affected work |

## Project layout

```
apps/
  shop-web/                         composes feature libs; routing, app shell only
  shop-api/
  shop-web-e2e/
libs/
  shop/
    feature-checkout/               smart components / use-case orchestration   tags: scope:shop, type:feature
    ui-product-card/                presentational components                    tags: scope:shop, type:ui
    data-access-orders/             API clients, state, repositories             tags: scope:shop, type:data-access
    domain/                         entities, rules, schemas (pure)              tags: scope:shop, type:domain
  shared/
    ui/                             design system                                tags: scope:shared, type:ui
    util-formatting/                pure helpers                                 tags: scope:shared, type:util
tools/generators/                   local generators (new feature lib with the right tags)
nx.json                             targetDefaults, namedInputs, cache config
```

Allowed dependencies (enforced): `app → feature → (ui, data-access) → domain → util`; `scope:X → scope:X | scope:shared`; `type:util` depends only on `type:util`. Apps never import other apps; libraries never import apps.

## Conventions

- Every project has `tags` (`scope:*`, `type:*`) in `project.json`; untagged projects fail lint.
- Libraries expose a public API through `src/index.ts`; imports use the path alias (`@acme/shop/data-access-orders`), never relative paths across projects.
- Create projects only with generators (`nx g`), so config, tags and targets are consistent.
- One file = one component/service/function; libraries stay small and focused (split when a lib has two reasons to change).
- Targets have the same names everywhere: `build`, `serve`, `test`, `lint`, `e2e`.
- `namedInputs` exclude tests and docs from production build inputs so caching stays effective.
- New feature = `libs/<scope>/feature-<name>` (+ data-access/ui libs if needed) via the local generator, then imported by the app.

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Serve | `nx serve shop-web` |
| Build | `nx build shop-web` |
| Affected | `nx affected -t lint test build --base=origin/main` |
| Test project | `nx test data-access-orders` |
| Lint | `nx run-many -t lint` |
| Format | `nx format:write` |
| Graph | `nx graph` |
| New lib | `nx g @nx/js:lib libs/shop/domain --tags=scope:shop,type:domain` |
| Release | `nx release` |

## Testing

- Every library has its own test target; domain and util libs are fully unit tested.
- data-access libs test against mocked HTTP (MSW) or a test database.
- UI libs: component tests with Testing Library; stories for visual review.
- e2e projects (`*-e2e`) cover critical journeys of each app.
- CI runs `nx affected -t test` so a change only re-tests the projects that depend on it.

## Quality gates

- `nx affected -t lint test build` passes; module boundary violations are lint errors.
- `nx format:check` clean; TypeScript strict with no errors.
- No circular dependencies in the project graph.
- Cache hits are expected in CI: a task that never caches needs its inputs/outputs fixed.

## Dependencies

- Single version policy: one `package.json` at the root for third-party dependencies.
- Upgrade Nx and its plugins only with `nx migrate latest` + `nx migrate --run-migrations`.
- Do NOT use: relative imports across projects, wildcard tags, disabling `enforce-module-boundaries`, barrel files that re-export other libraries, hand-written `project.json` for new projects (use generators).

## Rules for agents

- Before adding an import across libraries, check the tags allow it; if not, move the code or create a lib with the right type.
- Create libraries and components with `nx g`, never by copying folders.
- Run only affected targets (`nx affected`) to verify a change, plus the specific project.
- Keep apps thin: new logic goes in a library.
- Never relax a boundary rule in `eslint.config` to make a change pass.
- Add new public symbols to the library's `index.ts`; keep internals unexported.
- Upgrade Nx only via `nx migrate`.
- Domain libs import nothing framework-specific.
