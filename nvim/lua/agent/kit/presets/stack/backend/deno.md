<!-- name: Deno 2 + Hono -->
<!-- desc: TypeScript API on Deno 2: Hono, JSR packages, built-in test/lint/fmt, permissions as a security boundary -->

# STACK.md: Deno 2 + Hono

## Summary

An HTTP API on Deno 2 with Hono. TypeScript runs directly, the toolchain is built in (test, lint, fmt, check, compile) and
permissions limit what the process can touch. Packages come from JSR (and npm when needed). Hexagonal layout: handlers and
storage are adapters around use cases with no Deno-specific imports.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript (Deno 2 built-in compiler, strict) | No build step, typed |
| Runtime | Deno 2.x | Secure by default, web-standard APIs |
| Web | Hono 4 (`jsr:@hono/hono`) | Small, standard Request/Response |
| Validation | Zod (`npm:zod`) or `jsr:@std/` validators | Typed input |
| Data | PostgreSQL via `jsr:@db/postgres` or Deno KV for small apps | SQL or built-in KV |
| Config | `Deno.env` read once in `config.ts` | One place, validated |
| Testing | `deno test` + `jsr:@std/assert` | Built in |
| Lint/format | `deno lint`, `deno fmt` | Built in, zero config |
| Deploy | Deno Deploy or `deno compile` binary in a container | One artifact |

## Project layout

```
deno.json                     tasks, imports map, lint/fmt config
main.ts                       composition root: config, adapters, Hono app, Deno.serve
src/
  config.ts
  features/
    notes/
      notes_routes.ts         HTTP adapter
      notes_service.ts        use cases
      notes_repo.ts           port
      notes_repo_pg.ts        Postgres adapter
      notes_repo_memory.ts    in-memory adapter (tests, dev)
      notes_test.ts
  shared/
    errors.ts
    http_errors.ts            domain error → status, in one place
```

Dependency direction: `routes → service → repo port ← adapters`; only `main.ts` and adapters touch `Deno.*`.

## Conventions

- Imports through the `imports` map in `deno.json`; pin JSR/npm versions there.
- Run with the narrowest permissions: `--allow-net=0.0.0.0:8000 --allow-env=DATABASE_URL,PORT`.
- Use web standards (`fetch`, `Request`, `URL`, `crypto.subtle`) before any library.
- File names snake_case; one responsibility per file.

## Commands

| Task | Command |
| --- | --- |
| Dev | `deno task dev` (`deno run --watch --allow-net --allow-env main.ts`) |
| Test | `deno test --allow-env` |
| Check | `deno check main.ts` |
| Lint | `deno lint` |
| Format | `deno fmt` |
| Compile | `deno compile --allow-net --allow-env -o app main.ts` |

## Testing

- Services with the in-memory repo; routes via `app.request()` (Hono) without a server.
- Postgres adapter tests against a real database, skipped unless `DATABASE_URL` is set.

## Quality gates

- `deno fmt --check`, `deno lint`, `deno check`, `deno test` all clean.
- No `--allow-all` anywhere (tasks, Dockerfile, docs).

## Dependencies

- JSR first, then npm with `npm:` specifiers; pin versions in `deno.json`.
- Do NOT use: Node-specific packages when a web standard exists, `--allow-all`, `node_modules` checked in.

## Rules for agents

- Never widen permissions to make something work: name the exact host, env var or path.
- Keep `Deno.*` calls in `main.ts` and adapters only.
- Every request body is validated before it reaches a service.
- Add new imports to `deno.json`'s import map; no inline URLs in code.
- Tests live next to code as `*_test.ts`; run `deno test` before finishing.
- Map domain errors to HTTP in `http_errors.ts` only.
- Prefer `jsr:@std/*` over third-party utilities.
- Keep files under ~250 lines.
