<!-- name: SolidJS + Vite -->
<!-- desc: fine-grained reactivity, no virtual DOM: SolidJS, Vite 8, TypeScript 7, Solid Router, TanStack Query -->

# STACK.md: SolidJS + Vite

## Summary

A single-page application in SolidJS: JSX compiled to real DOM updates driven by signals, with no virtual DOM and a small
runtime (~7 KB gzip). Vite 8 builds it with Rolldown. Server state lives in TanStack Query for Solid; local state in
signals and stores. Feature-organised: each feature owns its components, resources and logic; pure logic never imports
Solid.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript 7 (native `tsc`, `strict`) | Types end to end, fast checks |
| UI | SolidJS 1.9+ | Fine-grained reactivity, top-tier runtime performance |
| Build | Vite 8 (Rolldown) + `vite-plugin-solid` | Fast dev, small bundles |
| Routing | `@solidjs/router` (lazy routes) | Official, code splitting per route |
| Server state | `@tanstack/solid-query` | Caching, retries, invalidation |
| Local state | Signals, `createStore` for nested state | Built in |
| Forms | `@modular-forms/solid` + Valibot | Small, typed |
| Styling | Tailwind CSS 4 (or CSS modules) | No runtime CSS |
| Testing | Vitest + `@solidjs/testing-library` + Playwright | Unit, component, flows |
| API mocking | MSW | Same mocks in tests and dev |
| Lint/format | ESLint (`eslint-plugin-solid`, `typescript-eslint` strict) + Prettier | Catches reactivity mistakes |
| Package manager | pnpm | Fast, strict |
| Deploy | Static files on a CDN | |

## Project layout

```
src/
  main.tsx                       render(<App/>), QueryClientProvider, Router
  app/
    routes.tsx                   route table with lazy() pages
    layout.tsx                   shell: nav, error boundary, Suspense
  core/
    api/client.ts                fetch wrapper: base URL, auth header, typed errors
    ui/                          shared primitives (button.tsx, dialog.tsx), one per file
  features/
    orders/
      api/orders.queries.ts      createQuery/createMutation factories + query keys
      api/orders.schema.ts       Valibot schemas of API payloads
      domain/order.ts            types + pure rules (no Solid imports)
      components/order-list.tsx
      components/order-row.tsx
      pages/orders.page.tsx      composes components, reads route params
      domain/order.test.ts
mocks/handlers.ts                MSW handlers
e2e/
```

Dependency direction: `pages → components → api → core`; `domain` is imported by all and imports nothing from Solid or
`core/api`. Features never import another feature's internals.

## Conventions

- Never destructure props (it breaks reactivity): read `props.x`, or use `splitProps`/`mergeProps`.
- Derived values are functions or `createMemo`, never copies of signals into variables.
- Side effects only in `createEffect`/`onMount`/`onCleanup`; no effects that set other signals when a memo would do.
- Use `<Show>`, `<For>`, `<Switch>` instead of ternaries and `.map` in JSX.
- Server data only through query factories in `*.queries.ts`; components never call `fetch`.
- One component per file; files over ~200 lines are split.

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Dev | `pnpm dev` |
| Build | `pnpm build` (`tsc --noEmit && vite build`) |
| Typecheck | `pnpm typecheck` |
| Test | `pnpm test` (`vitest run`) |
| E2E | `pnpm test:e2e` |
| Lint | `pnpm lint` |

## Testing

- Domain: plain Vitest unit tests.
- Components: `@solidjs/testing-library` with MSW for data; assert what the user sees.
- Flows: Playwright on the production build.
- Each query factory has a test of its error path.

## Quality gates

- `tsc --noEmit`, ESLint (with `solid/reactivity`) zero warnings, Prettier check.
- Budgets: initial JS ≤ 60 KB gzip, each route chunk ≤ 30 KB gzip, LCP ≤ 2.0 s, INP ≤ 200 ms (mobile profile).
- E2E smoke suite green.

## Dependencies

- Solid primitives and the platform first; `@solid-primitives/*` before writing a hook of your own.
- Do NOT use: React libraries through compat layers, Redux/MobX (signals and stores cover it), Axios, CSS-in-JS runtimes, Moment.js.

## Rules for agents

- Never destructure props or signal values at component top level.
- Never call `fetch` in a component; add a query/mutation factory.
- Every route page is `lazy()` loaded.
- Every async boundary has `<Suspense>` with a skeleton and an `<ErrorBoundary>` with retry.
- Mutations invalidate the exact query keys they affect.
- Keep `domain/` free of Solid imports so it is testable anywhere.
- Lists with identity use `<For>`; index-based lists use `<Index>`.
- Respect the bundle budgets; check the build report when adding a dependency.
