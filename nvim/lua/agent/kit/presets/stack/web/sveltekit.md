<!-- name: SvelteKit -->
<!-- desc: SvelteKit with Svelte 5 runes, TypeScript, form actions, Drizzle + Postgres, Tailwind, Vitest, Playwright -->

# STACK.md: SvelteKit

## Summary

A full web application on SvelteKit and Svelte 5 (runes) in strict TypeScript. Data is loaded on the server in `load`
functions and mutated through form actions that work without JavaScript and are progressively enhanced. Business
rules live in plain TypeScript under `$lib/server`, behind repository interfaces, so routes stay thin.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript 7 (native `tsc`; fall back to 6.x if `svelte-check` lags) (`strict`) | Types generated for routes (`./$types`) |
| Framework | SvelteKit 2 | SSR, file routing, load functions, form actions |
| UI | Svelte 5 (runes: `$state`, `$derived`, `$effect`, `$props`) | Explicit fine-grained reactivity |
| Validation | Zod (or Valibot) + `sveltekit-superforms` for complex forms | One schema client and server |
| Database | PostgreSQL | |
| Data access | Drizzle ORM + `drizzle-kit` | Typed SQL, file migrations |
| Auth | Lucia-style sessions in `hooks.server.ts` (or Auth.js for SvelteKit) | Session on `event.locals` |
| Styling | Tailwind CSS 4 | Tokens in the theme |
| Unit tests | Vitest + `@testing-library/svelte` | |
| E2E tests | Playwright | |
| Lint/format | ESLint (`eslint-plugin-svelte`, `typescript-eslint`) + Prettier (`prettier-plugin-svelte`) + `svelte-check` | |
| Adapter | `@sveltejs/adapter-node` (or the host's adapter) | |
| Package manager | pnpm | |

## Project layout

```
src/
  hooks.server.ts                  session → event.locals, security headers
  app.d.ts                         Locals, PageData types
  routes/
    +layout.svelte
    (app)/+layout.server.ts        auth guard for the group
    (app)/orders/+page.server.ts   load + actions: validate → service → return data / fail(422)
    (app)/orders/+page.svelte
    (app)/orders/[id]/+page.server.ts
    api/webhooks/+server.ts        endpoints only for external callers
  lib/
    components/ui/                 primitives (Button.svelte, Field.svelte…)
    features/orders/
      OrderTable.svelte
      OrderForm.svelte
      schemas.ts                   Zod schemas (shared)
    server/                        never imported from client code (SvelteKit enforces it)
      db/schema.ts                 Drizzle schema
      db/client.ts
      orders/order.ts              domain types and rules
      orders/order-repository.ts   interface
      orders/order-repository.drizzle.ts
      orders/place-order.ts        one use case per file
    env.ts
drizzle/                           migrations
tests/e2e/
```

Dependency direction: `routes → $lib/features (UI) and $lib/server (use cases) → domain`; domain files import nothing
from SvelteKit, Svelte or Drizzle. `$lib/server` is unreachable from the browser by design.

## Conventions

- One file = one responsibility: one component, one use case, one repository. Components over ~200 lines are split.
- Reads in `+page.server.ts` `load`; writes in form `actions`; `+server.ts` only for APIs called by others.
- Actions validate with Zod and return `fail(422, { errors, values })` on invalid input; forms use `use:enhance`.
- Svelte 5 runes only: `$props()` instead of `export let`, `$state`/`$derived` instead of `$:`; `$effect` only for side effects on the outside world.
- Shared client state in `.svelte.ts` modules with runes, created per request through context (never module-level state on the server).
- Env through `$env/static/private` / `$env/dynamic/private` in server files only.
- New feature = domain + repository + use case in `$lib/server/<feature>` → route `load`/actions → components in `$lib/features/<feature>`.

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Dev | `pnpm dev` |
| Build | `pnpm build` |
| Preview | `pnpm preview` |
| Type check | `pnpm svelte-kit sync && pnpm svelte-check --tsconfig ./tsconfig.json` |
| Lint | `pnpm lint` |
| Format | `pnpm prettier --write .` |
| Unit tests | `pnpm vitest run` |
| E2E tests | `pnpm playwright test` |
| Migrations | `pnpm drizzle-kit generate && pnpm drizzle-kit migrate` |

## Testing

- Domain and use cases: Vitest with in-memory repositories.
- Repositories: integration tests against a real Postgres (Docker/testcontainers).
- `load` and actions: call them with a fake `event` and assert returned data and `fail` results.
- Components with logic: `@testing-library/svelte`.
- Playwright for critical flows, including one run with JavaScript disabled for forms.

## Quality gates

- `svelte-check` with zero errors and warnings; `tsc` strict.
- ESLint `--max-warnings 0`, Prettier clean.
- Vitest and Playwright green in CI; `pnpm build` succeeds.

## Dependencies

- Platform first: SvelteKit's `fetch`, form actions, `Intl`.
- Allowed: the table above; anything else needs a reason in the PR.
- Do NOT use: Svelte 4 stores/`$:` syntax in new code, client-side data fetching libraries for data a `load` can provide, Axios, heavy component libraries that fight Tailwind, ORMs other than Drizzle.

## Rules for agents

- Use Svelte 5 runes syntax only; never write `export let` or `$:` in new code.
- Never import `$lib/server` or private env from a `.svelte` file or universal `+page.ts`.
- Mutations are form actions with `use:enhance`; they must work without JavaScript.
- Validate every action input with Zod; return `fail(422, …)` with the submitted values on error.
- Never keep per-user state in module-level variables (shared across requests on the server).
- Business rules go in `$lib/server/<feature>`; routes only load, validate and call.
- Every schema change has a Drizzle migration; never edit an applied migration.
- Use `$lib/components/ui` primitives; label every input and icon button.
