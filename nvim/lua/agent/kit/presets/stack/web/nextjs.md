<!-- name: Next.js App Router -->
<!-- desc: Next.js App Router, TypeScript strict, Server Components, Server Actions, Zod, Tailwind, shadcn/ui -->

# STACK.md: Next.js App Router

## Summary

A web application on Next.js (App Router) in strict TypeScript. Pages are React Server Components by default: data is
fetched on the server, close to where it is rendered, and only interactive leaves are Client Components. Mutations go
through Server Actions validated with Zod. Code is organised by feature; business rules live in plain TypeScript modules
that know nothing about React, Next.js or the database client.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript 7 (native `tsc`, `strict`, `noUncheckedIndexedAccess`; fall back to 6.x if `next build` type checking lags) | Types catch most bugs before runtime |
| Framework | Next.js 15 (App Router) | Server Components, streaming, Server Actions, file routing |
| UI | React 19 | Server and Client Components, `useActionState`, `useOptimistic` |
| Styling | Tailwind CSS 4 | Utility classes, tokens in the theme, no CSS files per component |
| Components | shadcn/ui (Radix primitives) | Accessible primitives, code owned in the repo |
| Validation | Zod | One schema for forms, actions, env and API input |
| Server state on the client | TanStack Query (only where needed) | Polling, infinite lists, client-driven refetch |
| Data access | Drizzle ORM + PostgreSQL (or the project's DB) | Typed SQL, migrations as files |
| Auth | Auth.js (NextAuth v5) or the platform's provider | Sessions on the server, middleware protection |
| Forms | React Hook Form + `@hookform/resolvers/zod` (complex forms) | Plain `<form action>` for simple ones |
| Unit tests | Vitest + Testing Library | Fast, ESM native |
| E2E tests | Playwright | Real browser, traces on failure |
| Lint/format | ESLint (`next/core-web-vitals`, `typescript-eslint` strict) + Prettier | One style, no debates |
| Package manager | pnpm | Fast, strict `node_modules` |

## Project layout

```
src/
  app/                              routes only: layouts, pages, loading/error states, route handlers
    (marketing)/page.tsx
    (app)/layout.tsx                authenticated shell
    (app)/orders/page.tsx           Server Component: calls features/orders/queries, renders components
    (app)/orders/[id]/page.tsx
    api/webhooks/stripe/route.ts    route handlers only for external callers
  features/
    orders/
      domain/order.ts               types and pure rules (no React, no DB)
      domain/order-status.ts
      queries.ts                    server-only reads ("server-only" import)
      actions.ts                    "use server": validate with Zod → use case → revalidatePath
      schemas.ts                    Zod schemas shared by form and action
      repository.ts                 OrderRepository interface
      repository.drizzle.ts         implementation with Drizzle
      components/order-table.tsx    Server Component
      components/order-form.tsx     "use client" leaf
  components/ui/                    shadcn/ui primitives (button.tsx, dialog.tsx…)
  lib/
    db/schema.ts                    Drizzle schema
    db/client.ts
    env.ts                          Zod-validated env (server and client parts)
    auth.ts
  styles/globals.css
drizzle/                            generated migrations
tests/e2e/                          Playwright specs
```

Dependency direction: `app → features/*/components → features/*/{actions,queries} → features/*/domain`. `domain` imports
nothing from React, Next.js or `lib/db`. Features do not import each other's internals: only their exported entry points.

## Conventions

- Server Components by default; add `"use client"` only to the smallest interactive leaf. Never mark a page or layout as client.
- Modules that touch the database, secrets or env import `server-only`.
- One file = one responsibility: one component, one action group, one repository. Files over ~250 lines are split.
- Server Actions: parse input with the feature's Zod schema, authorize, call the use case, `revalidatePath`/`revalidateTag`, return a typed result `{ ok: true, data } | { ok: false, errors }`; never throw to the client for validation errors.
- Every route segment with data has `loading.tsx` and `error.tsx`; not-found uses `notFound()`.
- File names in kebab-case; components in PascalCase; hooks `use-x.ts` exporting `useX`.
- Config and secrets only through `lib/env.ts`; never read `process.env` elsewhere.
- New feature = `features/<name>/` (domain → schemas → repository → queries/actions → components) → route in `app/`.

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Dev | `pnpm dev` |
| Build | `pnpm build` |
| Type check | `pnpm tsc --noEmit` |
| Lint | `pnpm lint` |
| Format | `pnpm prettier --write .` |
| Unit tests | `pnpm vitest run` |
| E2E tests | `pnpm playwright test` |
| Migrations | `pnpm drizzle-kit generate && pnpm drizzle-kit migrate` |
| Add a UI primitive | `pnpm dlx shadcn@latest add <component>` |

## Testing

- Domain modules: Vitest unit tests, no mocks needed (pure functions).
- Server Actions and queries: Vitest with the repository interface faked; assert validation errors and authorization.
- Client components with logic: Testing Library, query by role and label, never by class names.
- Critical flows (sign in, checkout, create/edit): Playwright against a production build with a seeded test database.
- A bug fix starts with a failing test.

## Quality gates

- `tsc --noEmit` with zero errors; no `any` (lint rule), no `@ts-ignore` without a comment.
- ESLint with zero warnings (`--max-warnings 0`), Prettier clean.
- Vitest and Playwright green in CI; `next build` succeeds.
- Bundle: no Client Component imports a server-only module (enforced by `server-only`).

## Dependencies

- Platform first: `fetch`, Web APIs, Next.js caching, React 19 primitives.
- Allowed: the table above. A new runtime dependency needs a reason in the PR (size, maintenance, alternatives).
- Do NOT use: Redux (server state lives on the server; Zustand only if real client state appears), Axios (use `fetch`), CSS-in-JS runtimes (styled-components, Emotion: incompatible with Server Components), Moment.js (use `date-fns` or `Intl`), `pages/` router in new code.

## Rules for agents

- Never add `"use client"` to fix an error without understanding it; move the interactive part into its own leaf component.
- Never fetch data in a Client Component that a Server Component can pass down as props.
- Every Server Action validates its input with Zod and checks the session; treat it as a public endpoint.
- Never read `process.env` outside `lib/env.ts`; never expose a secret through a `NEXT_PUBLIC_` variable.
- Use shadcn/ui primitives from `components/ui/`; do not install another component library.
- Use `next/image`, `next/link` and `next/font`; never raw `<img>` for content images.
- Revalidate after every mutation (`revalidatePath`/`revalidateTag`); never rely on a manual refresh.
- Keep business rules in `features/*/domain`; components only render and call actions.
- Do not edit `components/ui/` primitives for one screen: compose or wrap them.
