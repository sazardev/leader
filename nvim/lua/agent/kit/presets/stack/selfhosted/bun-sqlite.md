<!-- name: Bun + Hono + SQLite -->
<!-- desc: tiny self-hosted TypeScript service: Bun runtime, Hono, bun:sqlite, one container or one compiled binary -->

# STACK.md: Bun + Hono + SQLite

## Summary

A small self-hosted service in TypeScript running on Bun: Hono for routing, the built-in `bun:sqlite` driver (no native
addon to compile), and either one small container or one executable built with `bun build --compile`. No database
server, no build step at runtime, tests with the built-in `bun test`. Designed for low memory, fast cold starts and
simple operations; backups of the SQLite file with Litestream or a nightly `VACUUM INTO` copy.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Runtime | Bun 1.3+ | Fast startup, TypeScript without a build step, built-in SQLite/test/bundler |
| Language | TypeScript (strict) | Types end to end |
| HTTP | Hono | Small, fast, Web-standard `Request`/`Response`, typed routes |
| Validation | Zod + `@hono/zod-validator` | One schema per input, inferred types |
| Database | `bun:sqlite` with WAL | Embedded, synchronous and fast, no driver to install |
| Queries | Drizzle ORM (`drizzle-orm/bun-sqlite`) or hand-written prepared statements | Typed SQL, migrations as files |
| Migrations | `drizzle-kit generate` + migrate at startup | Schema in git |
| Backups | Litestream (sidecar or wrapper) or nightly `VACUUM INTO` to S3 | Restorable copy off the server |
| Logging | JSON lines to stdout (`hono/logger` + a small structured logger) | Read with `docker logs` |
| Testing | `bun test` with an in-memory or temp-file database | Built in, fast |
| Lint | Biome (lint + format) and `tsc --noEmit` | One fast tool, types checked |
| Package manager | Bun (`bun install`, `bun.lock`) | Same tool as the runtime |
| Deploy | `oven/bun` (alpine/distroless) container, or `bun build --compile` binary + systemd | Smallest moving parts |

## Project layout

```
src/
  index.ts                  config, open DB (pragmas), migrate, build app, Bun.serve({ fetch: app.fetch })
  app.ts                    Hono app: middleware (logger, secure headers, error handler), mount feature routers
  config.ts                 env (Bun.env) → Zod-validated config
  db/
    client.ts               new Database(path); PRAGMA journal_mode=WAL, busy_timeout, foreign_keys
    schema.ts               Drizzle tables
    migrations/             generated SQL
  features/
    <feature>/
      routes.ts             Hono router: validate → service → JSON
      service.ts            rules and use cases
      repository.ts         queries for this feature
      schemas.ts            Zod input/output schemas
  lib/errors.ts             typed app errors → HTTP status in one handler
test/                       mirrors src/features
Dockerfile
```

Dependency direction: `index → app → features/*/routes → service → repository → db`. Routes never query the database.

## Conventions

- One feature per folder; routes, service, repository and schemas each in their own file.
- Every input validated with Zod at the route; services receive typed values.
- Errors are thrown as typed `AppError`s and turned into responses only in the app's `onError`.
- Prepared statements are created once and reused; writes in short transactions (`db.transaction`).
- Config only from env, validated at startup; the DB file lives on a volume (`/data/app.db`).
- `GET /healthz` runs `SELECT 1`.

## Commands

| Task | Command |
| --- | --- |
| Install | `bun install` |
| Dev | `bun --watch src/index.ts` |
| Test | `bun test` |
| Typecheck | `bunx tsc --noEmit` |
| Lint | `bunx biome check .` |
| Format | `bunx biome format --write .` |
| Generate migration | `bunx drizzle-kit generate` |
| Single binary | `bun build --compile --minify src/index.ts --outfile bin/app` |
| Container | `docker build -t app . && docker run -v app-data:/data -p 3000:3000 app` |

## Testing

- Services and repositories: `bun test` with a fresh database per test file (`:memory:` or a temp path) and migrations applied.
- Routes: call `app.request("/path", { method, body })` and assert status and JSON, through the real service and DB.
- A restore test copies the backup to a temp path and opens it.

## Quality gates

- `biome check` clean, `tsc --noEmit` with `strict` clean, `bun test` green.
- The image runs as a non-root user and idles under 60 MB RSS.

## Dependencies

- Bun built-ins first (`bun:sqlite`, `Bun.serve`, `Bun.password`, `bun test`), then Hono, Zod, Drizzle.
- Do NOT use: `better-sqlite3`/`sqlite3` native addons (use `bun:sqlite`), Express, Jest/Vitest (use `bun test`), Node-only APIs without checking Bun support, a separate database server at this size.

## Rules for agents

- Use Bun's built-ins before adding a package; check Bun compatibility for any Node-specific library.
- Never open the database without the WAL, busy_timeout and foreign_keys pragmas from `db/client.ts`.
- Validate every request input with Zod at the route.
- Routes never touch the database; they call the feature's service.
- Never build SQL with string interpolation; use Drizzle or prepared statements with parameters.
- Every schema change is a generated migration committed with the change.
- Keep the container non-root and the database on a volume, never in the image.
- Run `bun test`, `tsc --noEmit` and `biome check` before finishing.
