<!-- name: React + Vite SPA -->
<!-- desc: React SPA: Vite, TypeScript, TanStack Router + Query, Zustand, React Hook Form + Zod, Vitest, MSW -->

# STACK.md: React + Vite SPA

## Summary

A single-page application in React and strict TypeScript, built with Vite, talking to a separate HTTP API. Server state
(anything that comes from the API) is owned by TanStack Query; the URL is state through TanStack Router; the little real
client state left lives in small Zustand stores. Code is organised by feature, and the API is reached only through
typed client modules, so components never know about URLs or fetch.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript 7 (native `tsc`, `strict`, `noUncheckedIndexedAccess`) | Type safety end to end |
| Build | Vite 8 (Rolldown bundler) | Instant dev server, fast Rust-based builds |
| UI | React 19 | Components, Suspense, transitions |
| Routing | TanStack Router (file-based) | Type-safe routes, params and search params, loaders |
| Server state | TanStack Query 5 | Caching, retries, invalidation, optimistic updates |
| Client state | Zustand (only for cross-component UI state) | Tiny, no boilerplate |
| Forms | React Hook Form + Zod (`@hookform/resolvers`) | Performant forms, one schema for types and validation |
| API types | Zod schemas or OpenAPI-generated types (`openapi-typescript`) | Responses parsed at the boundary |
| Styling | Tailwind CSS 4 + Radix primitives (or shadcn/ui) | Tokens in the theme, accessible primitives |
| Unit tests | Vitest + Testing Library + `user-event` | Fast, same config as Vite |
| API mocking | MSW 2 | Same mocks in tests, Storybook and dev |
| E2E tests | Playwright | Real browser flows |
| Lint/format | ESLint (`typescript-eslint` strict, `react-hooks`, `jsx-a11y`) + Prettier | |
| Package manager | pnpm | |

## Project layout

```
src/
  main.tsx                         bootstraps router, QueryClient, providers
  routes/                          TanStack Router file routes: params, loaders, route components only
    __root.tsx
    index.tsx
    orders/index.tsx
    orders/$orderId.tsx
  features/
    orders/
      api/orders-client.ts         HTTP calls + Zod parsing of responses
      api/order-schemas.ts         Zod schemas and inferred types
      hooks/use-orders.ts          useQuery wrappers with query keys
      hooks/use-create-order.ts    useMutation + invalidation
      domain/order-total.ts        pure rules (no React, no fetch)
      components/order-list.tsx
      components/order-form.tsx
      query-keys.ts                key factory for the feature
  shared/
    api/http.ts                    fetch wrapper: base URL, auth header, error mapping
    ui/                            design-system primitives (button.tsx, dialog.tsx…)
    stores/ui-store.ts             Zustand store for global UI state (sidebar, theme)
    lib/env.ts                     Zod-validated import.meta.env
  test/
    msw/handlers.ts
    setup.ts
e2e/                               Playwright specs
```

Dependency direction: `routes → features/*/components → features/*/hooks → features/*/api → shared/api`;
`features/*/domain` imports nothing. Features import each other only through an `index.ts` public surface.

## Conventions

- One file = one responsibility: one component, one hook, one client module. Files over ~250 lines are split.
- Components never call `fetch`: they use feature hooks; hooks never build URLs: they use the feature's api client.
- Every API response is parsed with Zod at the boundary; inside the app, types are trusted.
- Query keys come from the feature's key factory; mutations invalidate exactly the keys they affect.
- Search params that matter (filters, pagination, tabs) live in the URL, validated by the route's schema.
- Zustand only for state no server owns and no URL should hold; never copy server data into a store.
- File names kebab-case, components PascalCase, hooks `useX`.
- New feature = `features/<name>/` (schemas → api client → hooks → components) → route file.

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Dev | `pnpm dev` |
| Build | `pnpm build` |
| Preview build | `pnpm preview` |
| Type check | `pnpm tsc -b` |
| Lint | `pnpm lint` |
| Format | `pnpm prettier --write .` |
| Unit tests | `pnpm vitest run` |
| E2E tests | `pnpm playwright test` |
| API types | `pnpm openapi-typescript <spec> -o src/shared/api/schema.d.ts` |

## Testing

- Domain functions: plain Vitest unit tests.
- Hooks and components: Testing Library with MSW handlers for the API; query by role/label, interact with `user-event`.
- Each feature tests loading, empty, error and success states of its main view.
- Playwright for critical flows against `vite preview` with MSW or a seeded backend.
- A bug fix starts with a failing test.

## Quality gates

- `tsc -b` clean, no `any`, no non-null assertions without a comment.
- ESLint `--max-warnings 0` (including `react-hooks/exhaustive-deps` and `jsx-a11y`), Prettier clean.
- Vitest with coverage on `domain` and `hooks`; Playwright green in CI.
- Bundle size checked on build (route-level code splitting through the router).

## Dependencies

- Platform first: `fetch`, `Intl`, `URLSearchParams`, `structuredClone`.
- Allowed: the table above; anything else needs a reason in the PR.
- Do NOT use: Redux / Redux Toolkit (Query + Zustand cover it), Axios (use the fetch wrapper), React Router alongside TanStack Router, Moment.js, Formik, `useEffect` for data fetching, CSS-in-JS runtimes.

## Rules for agents

- Never fetch inside `useEffect`; use a TanStack Query hook in the feature.
- Never store API data in Zustand or `useState`; read it from the query cache.
- Every mutation invalidates or updates the affected query keys from the key factory.
- Every form uses React Hook Form with the feature's Zod schema; show field errors next to the field.
- Parse every response with Zod in the api client; never cast with `as`.
- Read env only through `shared/lib/env.ts`; never put secrets in `VITE_` variables (they ship to the browser).
- Use the `shared/ui` primitives; do not add another component library.
- Keep route files thin: params, loader, and a feature component.
- Every list view handles loading, empty, error and paginated states.
