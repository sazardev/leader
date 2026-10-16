<!-- name: React Router 7 (framework) -->
<!-- desc: React Router 7 framework mode (ex-Remix): loaders/actions, SSR, TS 7, Vite, Vitest + Playwright -->

# STACK.md: React Router 7 (framework mode)

## Summary

A full web application on React Router 7 in framework mode (the successor of Remix): routes declare a `loader` for data
and an `action` for mutations, rendered on the server and progressively enhanced in the browser. Forms post to actions,
so most data flow needs no client state library. Domain logic lives outside routes in feature modules.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript 7 (native `tsc`, strict; fall back to 6.x if `react-router typegen` lags) | Typed loaders and actions |
| Framework | React Router 7 (framework mode, Vite plugin) | Loaders/actions, SSR, nested routes |
| UI | React 19 | Server rendering, actions |
| Styling | Tailwind CSS 4 | Tokens in CSS, no runtime |
| Validation | Zod | Parse form data and params |
| Data | Drizzle ORM + PostgreSQL | Typed SQL |
| Testing | Vitest + Testing Library; Playwright for flows | Unit and end-to-end |
| Lint | ESLint flat config + typescript-eslint | Strict |
| Package manager | pnpm | Strict, fast |
| Deploy | Node server (`react-router-serve`) in a container | One process |

## Project layout

```
app/
  root.tsx                       document, error boundary
  routes.ts                      route config
  routes/
    invoices._index.tsx          loader + component
    invoices.$id.tsx             loader + action + component
  features/
    invoices/
      invoices.server.ts         queries and mutations (server only)
      invoices.schema.ts         Zod schemas for form data
      invoice-table.tsx          UI component
      invoices.test.ts
  components/ui/                 buttons, inputs, dialogs
  lib/db.server.ts               Drizzle client
e2e/invoices.spec.ts
```

Dependency direction: `routes → features → lib`; `*.server.ts` never imported by client-only code.

## Conventions

- Data reads in `loader`, writes in `action`; components read `useLoaderData`, forms use `<Form>`/`useFetcher`.
- Parse every `formData`/`params` with Zod in the action/loader; return typed errors for the form to render.
- Server-only code in `*.server.ts`; secrets never reach the client bundle.
- One route module per URL; shared UI in `features/` or `components/`.

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Dev | `pnpm dev` |
| Typecheck | `pnpm react-router typegen && pnpm tsc --noEmit` |
| Test | `pnpm vitest run` |
| E2E | `pnpm playwright test` |
| Build | `pnpm build` |
| Start | `pnpm start` |

## Testing

- Feature logic unit-tested; route modules tested by calling loaders/actions with a `Request`.
- Playwright covers the main flows with JavaScript disabled once (progressive enhancement).

## Quality gates

- `tsc --noEmit` (after typegen), ESLint clean, Vitest and Playwright green, `pnpm build` succeeds.
- JS budget: route chunks < 100 KB gzip; LCP < 2.5 s on the main pages.

## Dependencies

- React Router, React, Zod, Drizzle, Tailwind.
- Do NOT use: client fetching libraries for data loaders already provide, global state stores for server data, `useEffect` data fetching.

## Rules for agents

- Fetch in loaders and mutate in actions; never `useEffect` + `fetch` for route data.
- Validate every action input with Zod and return field errors, not thrown strings.
- Keep secrets and DB access in `*.server.ts`.
- Use `<Form>` so pages work before JavaScript loads.
- Throw `data(…, { status })` responses for 404/403 and render them in error boundaries.
- Run `react-router typegen` after changing routes; use the generated `Route.*` types.
- One route file per URL; extract UI into feature components when a file passes ~200 lines.
- Revalidation is automatic after actions; do not hand-roll cache invalidation.
