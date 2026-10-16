<!-- name: Bun full stack (React) -->
<!-- desc: one Bun server: HTML imports + React 19 front end, API routes beside it, compiled to a single binary -->

# STACK.md: Bun full stack (React)

## Summary

A full-stack web application served by one Bun process: `Bun.serve` routes HTML imports (Bun bundles the React 19 front
end on the fly in development and ahead of time in production) next to the JSON API routes. No separate bundler, no
Node, no framework server. The whole app compiles with `bun build --compile` into a single executable. The server side
is hexagonal; the client is feature-organised and talks to the API through a typed client.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Runtime | Bun 1.3+ | Server, bundler, test runner and package manager in one |
| Language | TypeScript 7 for type checking (native `tsc --noEmit`), `strict` | Shared types client ↔ server |
| Server | `Bun.serve({ routes })` with HTML imports (`import index from "./web/index.html"`) | Front end and API in one process, HMR in dev |
| UI | React 19 | Mature ecosystem |
| Client data | TanStack Query | Caching, retries, invalidation |
| Validation | Zod schemas in `shared/`, used by server and client | One contract |
| Database | SQLite via `bun:sqlite` (single node) or Postgres via `Bun.sql` | Built in |
| Styling | Tailwind CSS 4 (`bun-plugin-tailwind`) | Bundled by Bun |
| Testing | `bun test` (+ happy-dom for components) + Playwright | |
| Lint/format | Biome | |
| Package manager | Bun | |
| Deploy | Single binary from `bun build --compile` (or the `oven/bun` image) | Copy one file and run |

## Project layout

```
src/
  server.ts                        Bun.serve({ routes: { "/": index, "/api/*": api } }); composition root
  config.ts                        env schema
  shared/
    orders.schema.ts               Zod schemas + inferred types used by both sides
  server/
    domain/orders/order.ts         entity + rules (no Bun imports)
    domain/orders/order-repo.ts    port
    app/orders/place-order.ts      use case
    http/orders.routes.ts          route handlers: parse with shared schema → use case → Response.json
    http/errors.ts                 domain error → status
    db/sqlite.ts                   Database instance, migrations at startup
    db/orders.repo.ts
  web/
    index.html                     <script type="module" src="./main.tsx">
    main.tsx                       createRoot, QueryClientProvider, router
    api/client.ts                  typed fetch using shared schemas
    features/orders/
      orders.queries.ts
      order-list.tsx
      orders.page.tsx
migrations/
```

Dependency direction: `server/http → server/app → server/domain`; `web → shared`; `server → shared`. `web` never
imports from `server`, `server` never from `web`.

## Conventions

- The API contract is the Zod schemas in `shared/`: the server parses requests with them, the client parses responses.
- API routes live under `/api/*`; everything else is served by the HTML import (client-side routing).
- SQL through `bun:sqlite` prepared statements or `Bun.sql` tagged templates only.
- One use case, one route group, one component per file; files over ~250 lines are split.

## Commands

| Task | Command |
| --- | --- |
| Install | `bun install` |
| Dev | `bun --hot src/server.ts` (HMR for the front end) |
| Test | `bun test` |
| E2E | `bunx playwright test` |
| Typecheck | `bunx tsc --noEmit` |
| Lint/format | `bunx biome check --write .` |
| Build | `bun build --compile --minify src/server.ts --outfile dist/app` |

## Testing

- Server domain/use cases: `bun test` with fakes.
- API: call the route handlers with `new Request(...)`; assert status and parsed body.
- Components: `bun test` + happy-dom + Testing Library; flows with Playwright against the compiled binary.

## Quality gates

- `tsc --noEmit`, Biome and `bun test` clean; Playwright smoke on the compiled binary.
- Budgets: initial JS ≤ 120 KB gzip, LCP ≤ 2.0 s, INP ≤ 200 ms; API p95 ≤ 100 ms on core routes.

## Dependencies

- Bun built-ins first (server, bundler, SQLite, SQL, password hashing, test runner).
- Do NOT use: Express/Next.js on top (the point is one Bun server), Webpack/Vite (Bun bundles), Axios, an ORM that hides SQL, Jest.

## Rules for agents

- Never import server code from `web/` or the reverse; share only through `shared/`.
- Every API route validates input with the shared schema and returns typed errors.
- Never build SQL by concatenation.
- Keep `server.ts` the only composition root and route table.
- New pages are lazy-loaded React routes; keep the initial bundle inside the budget.
- Run `tsc --noEmit` before finishing: Bun does not type check.
- Migrations are new files; never edit an applied one.
- The release artifact is the compiled binary; anything it needs at runtime is embedded or configured by env.
