<!-- name: Bun + Hono -->
<!-- desc: native Bun runtime: Hono on Bun.serve, Bun.sql (Postgres) or bun:sqlite, Zod, bun test; no Node toolchain -->

# STACK.md: Bun + Hono

## Summary

An HTTP API running on the Bun runtime with Hono as the router: Bun runs TypeScript directly, installs packages, tests
and bundles, so there is no separate Node toolchain. Data access uses Bun's built-in clients (`Bun.sql` for Postgres,
`bun:sqlite` for embedded databases). Hexagonal layout: the domain is plain TypeScript, Hono handlers and SQL
repositories are adapters.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Runtime | Bun 1.3+ | Fast startup, TS natively, built-in test runner, SQL clients |
| Language | TypeScript 7 for type checking (native `tsc --noEmit`), `strict` | Bun strips types; `tsc` checks them |
| HTTP | Hono 4 (`export default { fetch: app.fetch }` on `Bun.serve`) | Small, fast, Web-standard Request/Response |
| Validation | Zod + `@hono/zod-validator` | Typed input at the boundary |
| Database | PostgreSQL 16 via `Bun.sql` (or SQLite via `bun:sqlite` for single-node) | Built in, no driver dependency |
| Migrations | Plain SQL files applied by `scripts/migrate.ts` (or `dbmate`) | Explicit, reviewable |
| Config | `Bun.env` parsed by a Zod schema at startup | Fails fast |
| Logging | `pino` (JSON) or Hono `logger` in dev | Structured |
| Testing | `bun test` (+ `app.request()` for HTTP tests) | One tool |
| Lint/format | Biome | One fast tool for both |
| Package manager | Bun (`bun install`, `bun.lock`) | Same tool |
| Deploy | `bun build --compile` single binary, or the `oven/bun` image | |

## Project layout

```
src/
  index.ts                         composition root: config, db, repositories, services, app; export default { port, fetch }
  config.ts                        Zod-validated env
  domain/
    orders/
      order.ts                     entity + invariants (no Bun/Hono imports)
      order-repository.ts          port (interface)
      errors.ts
  app/
    orders/
      place-order.ts               use case (one per file)
      list-orders.ts
  adapters/
    http/
      app.ts                       Hono app, middleware, error handler (domain error → status)
      orders.routes.ts             routes → use cases; zValidator on input
    db/
      client.ts                    Bun.sql instance
      orders.repo.ts               implements OrderRepository with tagged SQL
migrations/0001_orders.sql
scripts/migrate.ts
test/                              mirrors src/ where tests are not colocated
```

Dependency direction: `adapters → app → domain`. `domain` imports nothing from Bun, Hono or `adapters`.

## Conventions

- SQL only through `Bun.sql` tagged templates (parameterised); never string concatenation.
- Handlers parse with Zod, call one use case, map the result; error mapping lives in one `onError`.
- Constructors receive dependencies; `index.ts` is the only place concrete adapters are created.
- Use Web APIs (`Request`, `Response`, `URL`, `crypto.subtle`) and Bun APIs (`Bun.password`, `Bun.file`) before packages.
- Files over ~300 lines are split; one use case per file.

## Commands

| Task | Command |
| --- | --- |
| Install | `bun install` |
| Dev | `bun --hot src/index.ts` |
| Test | `bun test` |
| Typecheck | `bunx tsc --noEmit` |
| Lint/format | `bunx biome check --write .` |
| Migrate | `bun scripts/migrate.ts` |
| Build | `bun build src/index.ts --compile --minify --outfile dist/api` |

## Testing

- Domain and use cases: `bun test` with in-memory fakes of the ports.
- HTTP: `app.request('/orders', …)` against the Hono app with fakes; assert status and JSON.
- Repositories: against a real Postgres (Docker) or a temp SQLite file, each test isolated.
- A bug fix starts with a failing test.

## Quality gates

- `tsc --noEmit` and `biome check` clean; `bun test` green with coverage on domain/app ≥ 80 %.
- p95 latency budget per endpoint measured in a load test (`oha` or `k6`) before release on critical paths.

## Dependencies

- Bun built-ins and Web APIs first (SQL, password hashing, file IO, test runner).
- Do NOT use: Express (use Hono), ORMs that hide SQL, `node-fetch`/Axios (`fetch` is built in), `dotenv` (Bun loads `.env`), Jest/ts-node/nodemon.

## Rules for agents

- Never import `bun:*` or Hono in `domain/`.
- Never build SQL by concatenation; use `Bun.sql` tagged templates.
- Every route validates input with Zod and returns typed errors through the central handler.
- Add a migration file for every schema change; never edit an applied one.
- Use `bun test`, not another test runner.
- Type check with `tsc --noEmit` before finishing: Bun alone does not check types.
- Secrets come from env validated in `config.ts`; never log them.
- Keep `index.ts` the only wiring point.
