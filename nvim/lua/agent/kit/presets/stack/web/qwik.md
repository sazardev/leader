<!-- name: Qwik + Qwik City -->
<!-- desc: Resumable web apps: Qwik components, Qwik City routes with loaders/actions, near-zero JS on load -->

# STACK.md: Qwik + Qwik City

## Summary

A web application on Qwik: the HTML is resumable, so the browser downloads JavaScript only for the interaction the user
triggers, which keeps load time near static-site levels. Qwik City adds file routing, `routeLoader$` for data and
`routeAction$` for mutations. Features own their components and server logic.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript 7 (strict; fall back to 6.x if Qwik's tooling lags) | Typed components |
| Framework | Qwik + Qwik City | Resumability, tiny initial JS |
| Styling | Scoped styles (`useStylesScoped$`) or Tailwind 4 | No runtime CSS |
| Validation | Zod via `zod$` in actions | Typed form handling |
| Data | Drizzle + PostgreSQL (server only) | Typed SQL |
| Testing | Vitest + Playwright | Unit and flows |
| Lint | ESLint (`eslint-plugin-qwik`) | Catches `$` boundary mistakes |
| Package manager | pnpm | Strict, fast |
| Deploy | A Qwik City adapter (Node, Cloudflare Pages, Vercel) | SSR at the edge or server |

## Project layout

```
src/
  routes/
    index.tsx                     page
    layout.tsx                    shared layout
    notes/
      index.tsx                   routeLoader$ + page
      [id]/index.tsx              routeLoader$ + routeAction$ + page
  features/
    notes/
      notes.server.ts             queries/mutations
      note-card.tsx               component$
      note-form.tsx
      notes.test.ts
  components/ui/
  lib/db.server.ts
```

Dependency direction: `routes → features → lib`; server modules only imported from loaders/actions.

## Conventions

- Data in `routeLoader$`, writes in `routeAction$` with `zod$` validation; forms with `<Form action={…}>`.
- Event handlers are `$` closures; capture only serializable values.
- `useSignal`/`useStore` for local state; no global client stores for server data.
- Keep `useVisibleTask$` for browser-only work that must run eagerly (rare).

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Dev | `pnpm dev` |
| Typecheck | `pnpm tsc --noEmit` |
| Test | `pnpm vitest run` |
| E2E | `pnpm playwright test` |
| Build | `pnpm build` |
| Preview | `pnpm preview` |

## Testing

- Feature logic and server functions unit-tested; Playwright covers each route's main interaction.

## Quality gates

- Typecheck, lint, tests and `pnpm build` clean; initial JS on the home page < 10 KB gzip.

## Dependencies

- Qwik, Qwik City, Zod, Drizzle.
- Do NOT use: React-style client data fetching, libraries that need eager hydration, `useVisibleTask$` for data loading.

## Rules for agents

- Put every `$` boundary where Qwik needs it; never capture non-serializable values (class instances, functions) in closures.
- Load data with `routeLoader$`; mutate with `routeAction$`.
- Validate actions with `zod$` and return field errors.
- Keep server code in `*.server.ts`.
- Avoid `useVisibleTask$` unless the work is truly browser-only and visible.
- One route folder per URL; components in `features/`.
- Check the initial JS budget after adding interactive components.
- Use `<Link>` for navigation to keep SPA transitions.
