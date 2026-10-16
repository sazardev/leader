<!-- name: Bun + Elysia -->
<!-- desc: Elysia on Bun: TypeBox validation, end-to-end types to the client with Eden, OpenAPI generated -->

# STACK.md: Bun + Elysia

## Summary

An HTTP API on the Bun runtime with Elysia: schemas declared once with TypeBox give runtime validation, TypeScript types,
OpenAPI docs and, through Eden Treaty, a fully typed client for the front end with no code generation. Hexagonal layout:
Elysia plugins are the HTTP adapter around plain TypeScript use cases and domain.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Runtime | Bun 1.3+ | Fast, TS natively, built-in test runner and SQL |
| Language | TypeScript 7 for type checking (native `tsc --noEmit`), `strict` | Eden types depend on correct inference |
| HTTP | Elysia 1.x | Ergonomic, fast, schema-first |
| Validation | TypeBox (`t` from Elysia) | Runtime checks + static types from one schema |
| Client types | `@elysiajs/eden` (Treaty) | End-to-end type safety to the front end |
| API docs | `@elysiajs/openapi` (or `@elysiajs/swagger`) | Generated from the schemas |
| Database | PostgreSQL via `Bun.sql`, or Drizzle ORM if the team wants a query builder | Typed SQL |
| Migrations | SQL files (`dbmate`) or `drizzle-kit` | Reviewable |
| Auth | `@elysiajs/jwt` + `@elysiajs/bearer`, or session cookies | Plugins |
| Testing | `bun test` + Eden Treaty against the in-process app | Typed tests |
| Lint/format | Biome | |
| Package manager | Bun | |
| Deploy | `bun build --compile` binary or `oven/bun` image | |

## Project layout

```
src/
  index.ts                         app = new Elysia().use(plugins…); export type App = typeof app; app.listen(PORT)
  config.ts                        env schema (TypeBox) checked at startup
  domain/
    users/user.ts                  entity, invariants
    users/user-repository.ts       port
  app/
    users/register-user.ts         use case
  adapters/
    http/
      error.plugin.ts              onError: domain errors → status + problem JSON
      auth.plugin.ts               derive({ user }) from token
      users.plugin.ts              new Elysia({ prefix: '/users' }) routes with t.Object schemas
    db/
      client.ts
      users.repo.ts
  schemas/users.schema.ts          TypeBox models shared by routes (and exported for docs)
test/users.test.ts                 treaty(app) calls
```

Dependency direction: `adapters → app → domain`. Elysia and TypeBox live only in `adapters/` and `schemas/`.

## Conventions

- Every route declares `body`, `query`, `params` and `response` schemas; responses are validated too.
- Feature routes are Elysia plugins with a `prefix`, composed in `index.ts`; never one giant file.
- Export `type App` for Eden; front ends import only the type, never server code.
- Use `derive`/`resolve` for request-scoped data (user, tenant), not globals.
- One use case per file; handlers stay thin.

## Commands

| Task | Command |
| --- | --- |
| Install | `bun install` |
| Dev | `bun --watch src/index.ts` |
| Test | `bun test` |
| Typecheck | `bunx tsc --noEmit` |
| Lint/format | `bunx biome check --write .` |
| Build | `bun build src/index.ts --compile --minify --outfile dist/api` |
| API docs | open `/openapi` on the dev server |

## Testing

- Use cases with in-memory port fakes.
- HTTP through `treaty(app)` in process: calls are typed, so a breaking schema change fails compilation of the tests.
- Repositories against a real database in integration tests.

## Quality gates

- `tsc --noEmit` (catches Eden breakages), Biome clean, `bun test` green.
- The OpenAPI document is generated in CI and diffed; breaking changes need a version bump.

## Dependencies

- Official `@elysiajs/*` plugins first.
- Do NOT use: Express middlewares via adapters, Zod alongside TypeBox for the same payloads, hand-written API clients (use Eden), Jest.

## Rules for agents

- Never add a route without request and response schemas.
- Never import server modules into a client; only `import type { App }`.
- Business rules stay in `domain`/`app`; plugins only adapt HTTP.
- Errors go through `error.plugin.ts`; do not return ad-hoc error shapes.
- Run `tsc --noEmit` after schema changes: Eden types are the contract.
- Every schema change that breaks clients is called out in the PR.
- Secrets from validated config only; never in code or logs.
- Keep `index.ts` the only composition point.
