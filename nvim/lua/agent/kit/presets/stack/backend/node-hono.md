<!-- name: TypeScript + Hono -->
<!-- desc: TS API on Node (or Bun): Hono, Zod, Drizzle ORM + Postgres, Vitest, Biome, pnpm -->

# STACK.md: TypeScript + Hono

## Summary

A typed HTTP API in TypeScript running on Node.js LTS (Bun works with the same code). Hono gives a small, fast,
Web-standard router; Zod validates every input and generates the OpenAPI document; Drizzle keeps SQL close and typed.
Hexagonal layout organised by feature: routes and repositories are adapters, the domain is plain TypeScript.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Runtime | Node.js 22 LTS (or Bun 1.x) | Stable, Web APIs (`fetch`, `Request`) built in |
| Language | TypeScript 7 (native `tsc`), `strict: true`, ESM | Types are the first line of tests |
| HTTP | `hono` + `@hono/node-server` | Small, Web-standard, typed routes and middleware |
| Validation / contract | `zod` + `@hono/zod-openapi` | One schema validates input and documents the API |
| Database | PostgreSQL 16 | Relational, transactional |
| DB access | `drizzle-orm` + `postgres` (postgres.js) driver | SQL-like, typed, no runtime magic |
| Migrations | `drizzle-kit generate` + `drizzle-kit migrate` | SQL migration files committed |
| Config | env → Zod schema parsed at startup | Fails fast on a bad config |
| Logging | `pino` | Structured JSON, fast |
| Auth | JWT via `hono/jwt` or sessions; passwords with `@node-rs/argon2` | Standard primitives |
| Testing | `vitest` + `app.request()` + `@testcontainers/postgresql` | Fast unit tests, real DB in integration |
| Lint / format | Biome (`@biomejs/biome`) | One fast tool for both |
| Package manager | pnpm | Strict, fast, workspace-ready |
| Build | `tsup` (or `tsc`) → `dist/` | Plain JS for production |

## Project layout

```
src/
  main.ts                          composition root: config, db, repositories, services, app, server
  app.ts                           builds the Hono app: middleware order, mounts feature routers, error handler
  config.ts                        Zod env schema + parsed config
  shared/
    errors.ts                      DomainError base + NotFound, Conflict, Validation
    result.ts                      small Result helpers (if used)
  modules/<feature>/
    domain/
      order.ts                     entity + invariants (plain TS, no imports from adapters)
      order-status.ts              value object
      order-repository.ts          port (interface)
    application/
      place-order.ts               one use case per file: class or function with injected ports
      place-order.test.ts          unit test with in-memory fakes
    infrastructure/
      drizzle-order-repository.ts  implements the port with Drizzle
      schema.ts                    Drizzle table definitions of the feature
    http/
      routes.ts                    OpenAPI routes (createRoute) → use case → response
      schemas.ts                   Zod request/response schemas
  http/
    error-handler.ts               DomainError → status + problem JSON, in ONE place
    middleware/                    one middleware per file (request-id.ts, auth.ts, logger.ts)
drizzle/                           generated SQL migrations
test/                              integration helpers (container setup, factories)
```

Dependency direction: `http → application → domain` and `infrastructure → domain`. `domain` imports nothing from Hono, Zod or Drizzle.

## Conventions

- One file = one responsibility; file names in `kebab-case`, one exported concept per file. Files over ~250 lines are split.
- No `any`; `unknown` + narrowing at boundaries. `noUncheckedIndexedAccess` and `exactOptionalPropertyTypes` on.
- Routes are thin: validated input (Zod) → one use case → typed response. No Drizzle calls in routes.
- Errors: throw `DomainError` subclasses from domain/application; the single error handler maps them to status codes.
- Dependencies are passed through constructors/factory functions from `main.ts`; no module-level singletons except config.
- Dates as ISO 8601 UTC strings on the wire; money as integer minor units.
- New feature = `modules/<feature>` with the four folders → mount its router in `app.ts`.

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install --frozen-lockfile` |
| Dev | `pnpm dev` (`tsx watch src/main.ts`) |
| Build | `pnpm build` (`tsup src/main.ts --format esm`) |
| Test | `pnpm test` (`vitest run`) |
| Single test | `pnpm vitest run src/modules/order/application/place-order.test.ts` |
| Typecheck | `pnpm typecheck` (`tsc --noEmit`) |
| Lint / format | `pnpm biome check --write .` |
| Migration | `pnpm drizzle-kit generate && pnpm drizzle-kit migrate` |

## Testing

- Domain and use cases: Vitest unit tests with in-memory fake repositories; no database, no HTTP.
- Routes: `app.request('/orders', { method: 'POST', body })` against the app with faked use cases; assert status and body schema.
- Repositories: integration tests with `@testcontainers/postgresql`, migrations applied, data reset per test.
- The OpenAPI document is generated in a test and compared to the committed `openapi.json` snapshot.
- A bug fix starts with a failing test.

## Quality gates

- `tsc --noEmit` with zero errors (strict); `biome check` clean (no warnings allowed).
- `vitest run --coverage` passes; domain and application above 80% lines.
- Drizzle migrations are generated from the schema and committed; CI fails if `drizzle-kit generate` produces a new file.
- `pnpm audit --prod` has no high or critical vulnerabilities.

## Dependencies

- Web standard APIs and Node built-ins first (`fetch`, `crypto`, `node:test` utilities when enough).
- Allowed: the table above; anything else needs a reason in the PR (size, maintenance, what it replaces).
- Do NOT use: Express or Koa (Hono replaces them); Prisma alongside Drizzle; `moment` (use `Date`/`Temporal` polyfill or `date-fns`); `lodash` for what the language does; class-validator (Zod is the single validation layer); `ts-node` in production.

## Rules for agents

- Never use `any` or `@ts-ignore`; fix the type or narrow `unknown` with Zod.
- Every request body, query and param is declared with a Zod schema in `schemas.ts` and validated by the route.
- Never call Drizzle from routes or use cases; only from `infrastructure`.
- Never build SQL with template strings of user input; use Drizzle builders or `sql` with placeholders.
- Throw `DomainError` subclasses; never return raw error messages from the database to clients.
- Change the schema in `schema.ts`, then generate a migration; never edit an applied migration.
- Keep `main.ts` the only place that wires concrete implementations.
- Every new use case ships with a unit test; every new route with a request test.
- Use `pnpm`, never `npm install` or `yarn` (one lockfile).
