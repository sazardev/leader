<!-- name: Preact + Signals -->
<!-- desc: React's API in ~4 KB: Preact, @preact/signals, Vite 8, TypeScript 7, preact-iso routing -->

# STACK.md: Preact + Signals

## Summary

A lightweight single-page application (or islands on a server-rendered page) built with Preact: the React component
model with a ~4 KB runtime. State uses `@preact/signals`, which update only the DOM that reads them. Vite 8 with the
Preact preset builds it. For teams that know React but need small bundles: low-end phones, embedded widgets, slow networks.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript 7 (native `tsc`, `strict`, `jsxImportSource: "preact"`) | Types, fast checks |
| UI | Preact 10 | ~4 KB runtime, React-like API |
| State | `@preact/signals` | Fine-grained updates, no context churn |
| Build | Vite 8 (Rolldown) + `@preact/preset-vite` | Fast dev, prerender support |
| Routing | `preact-iso` (`lazy`, `Router`, `prerender`) | Tiny, async routes, SSG |
| Data | `fetch` + signals-based resources (`core/resource.ts`) | No query library needed at this size |
| Validation | Valibot | Tree-shakable |
| Styling | CSS modules + custom properties | No runtime |
| Testing | Vitest + `@testing-library/preact` + Playwright | |
| Lint/format | ESLint (`typescript-eslint` strict) + Prettier | |
| Package manager | pnpm | |
| Deploy | Static files on a CDN (prerendered routes) | |

## Project layout

```
src/
  index.tsx                      hydrate/render, prerender entry
  app/
    app.tsx                      Router + layout + ErrorBoundary
    routes.ts                    lazy route table
  core/
    http.ts                      fetch wrapper, timeouts, typed errors
    resource.ts                  signal-backed async resource (data, error, loading, reload)
    ui/                          shared primitives, one per file
  features/
    search/
      search.state.ts            signals + actions (no JSX)
      search.api.ts              requests + Valibot parsing
      search-box.tsx
      results-list.tsx
      search.page.tsx
      search.state.test.ts
  styles/tokens.css
e2e/
```

Dependency direction: `*.page.tsx → components → *.state.ts → *.api.ts → core`. State modules import no JSX.

## Conventions

- Global/feature state lives in `*.state.ts` as signals; components read `signal.value` and call actions.
- Pass signals (not their values) to deep children to keep updates local.
- `computed` for derived values; `effect` only for real side effects, disposed on unmount.
- Never import from `react` directly; if a React library is unavoidable, alias through `preact/compat` and say why.
- One component per file; files over ~200 lines are split.

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Dev | `pnpm dev` |
| Build | `pnpm build` (`tsc --noEmit && vite build`, prerendered routes) |
| Typecheck | `pnpm typecheck` |
| Test | `pnpm test` |
| E2E | `pnpm test:e2e` |
| Lint | `pnpm lint` |

## Testing

- State modules: unit tests on signals and actions without rendering.
- Components: Testing Library assertions on visible text and roles.
- Flows: Playwright on the prerendered build.

## Quality gates

- Typecheck, lint (zero warnings) and format check clean.
- Budgets: initial JS ≤ 25 KB gzip, LCP ≤ 1.8 s, INP ≤ 200 ms, CLS ≤ 0.1 (mobile profile); fail CI over budget.

## Dependencies

- Preact, signals and the platform first.
- `preact/compat` only for a specific library, with its size in the PR.
- Do NOT use: React-only heavy libraries (MUI, large chart kits) through compat, Redux, Axios, CSS-in-JS runtimes, Moment.js.

## Rules for agents

- Keep state in signals in `*.state.ts`, not in `useState` chains across components.
- Never read `.value` of a signal at module top level in a component file (it breaks subscriptions).
- Every route is `lazy()` and prerenderable unless it needs auth.
- Every async view has loading, error (retry) and empty states.
- No JSX in state or API modules.
- Check the bundle report when adding a dependency; stay inside the budgets.
- Use semantic HTML and native elements (`<dialog>`, `<details>`) before custom widgets.
- Colors and spacing only from `tokens.css`.
