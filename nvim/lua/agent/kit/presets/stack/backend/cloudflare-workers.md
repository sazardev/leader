<!-- name: Cloudflare Workers + Hono -->
<!-- desc: TypeScript API at the edge: Hono on Workers, D1 (SQLite), KV and R2, wrangler, vitest-pool-workers -->

# STACK.md: Cloudflare Workers + Hono

## Summary

An HTTP API that runs on Cloudflare Workers: Hono for routing, D1 (SQLite) for relational data, KV for cached reads, R2 for
files. No servers, global by default. Bindings are injected through `env`, so the core logic stays testable with plain
inputs; the Worker entry only wires routes to use cases.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript 7 (native `tsc`, strict) | Typed bindings and handlers |
| Runtime | Cloudflare Workers (V8 isolates) | Global, cold starts in ms |
| Web | Hono 4 | Small, Workers-native, typed context |
| Validation | Zod + `@hono/zod-validator` | Typed input at the edge |
| Data | D1 + Drizzle ORM (`drizzle-orm/d1`) | SQL, migrations, types |
| Cache / files | Workers KV, R2 | Read-heavy data, blobs |
| Testing | Vitest + `@cloudflare/vitest-pool-workers` | Tests run in workerd with real bindings |
| Lint | Biome | One fast tool |
| Package manager | pnpm | Strict, fast |
| Deploy | `wrangler deploy` | Config in `wrangler.toml` |

## Project layout

```
src/
  index.ts                     Hono app: middleware, route modules, export default app
  env.ts                       Env type: D1, KV, R2 bindings and vars
  features/
    links/
      links.routes.ts          HTTP: validate, call the use case, respond
      links.service.ts         use cases on plain inputs (takes a LinksRepo)
      links.repo.ts            LinksRepo port
      links.repo.d1.ts         D1 implementation with Drizzle
      links.schema.ts          Zod schemas for requests/responses
      links.test.ts
  db/
    schema.ts                  Drizzle tables
migrations/                    drizzle-kit generated SQL
wrangler.toml
vitest.config.ts               pool: workers
```

Dependency direction: `routes → service → repo port ← repo.d1`. Services never read `env`; routes build the repo from `env`.

## Conventions

- One feature folder per resource; one responsibility per file (routes, service, repo, schema, test).
- No global state: everything per request comes from `c.env` and `c.var`.
- Errors: throw `HTTPException` in routes only; services return results or throw domain errors mapped in one `onError`.
- Keep each request under the CPU budget: no heavy work in the request path; use Queues or Cron Triggers for it.

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Dev | `pnpm wrangler dev` |
| Test | `pnpm vitest run` |
| Typecheck | `pnpm tsc --noEmit` |
| Lint | `pnpm biome check .` |
| Migrate (local) | `pnpm wrangler d1 migrations apply DB --local` |
| Deploy | `pnpm wrangler deploy` |

## Testing

- Services: unit tests with in-memory repos.
- Routes: `SELF.fetch` in the workers pool with real D1/KV bindings and applied migrations.
- Every route tests the happy path, validation failure and not-found.

## Quality gates

- `tsc --noEmit`, Biome clean, Vitest green in the workers pool.
- `wrangler deploy --dry-run` succeeds; bundle size reported in CI.

## Dependencies

- Hono, Zod, Drizzle, Vitest + pool-workers, Biome, wrangler.
- Do NOT use: Node-only packages (`fs`, `net`), Express, ORMs that need TCP connections, large polyfills.

## Rules for agents

- Read bindings only from `c.env`; never import secrets or create clients at module scope.
- Validate every request body and param with Zod before use.
- Never block on long work in a request: enqueue it.
- All SQL goes through Drizzle or prepared D1 statements; no string concatenation.
- New tables need a migration in `migrations/` applied locally before tests.
- Keep `index.ts` to wiring; logic belongs in services.
- Return JSON with explicit status codes; errors in one shape from `onError`.
- Check the Workers runtime supports an API before using it (no Node built-ins without `nodejs_compat`).
