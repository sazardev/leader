<!-- name: Nuxt 3 -->
<!-- desc: Nuxt 3 + Vue 3 Composition API, TypeScript, Pinia, Nitro server routes, Zod, Vitest, Playwright -->

# STACK.md: Nuxt 3

## Summary

A full web application on Nuxt 3 and Vue 3 (Composition API, `<script setup>`) in strict TypeScript. Pages render on
the server and hydrate; data comes from Nitro server routes through `useFetch`/`useAsyncData`. Business rules live in
plain TypeScript under `server/` behind repository interfaces; Vue components only present and call composables.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript 7 (native `tsc`; fall back to 6.x if `vue-tsc` lags) (`strict`, `typeCheck` in CI) | |
| Framework | Nuxt 3 (Nitro server) | SSR, file routing, server routes, auto-imports |
| UI | Vue 3.5, `<script setup lang="ts">` | Composition API, typed props/emits |
| State | Pinia (`@pinia/nuxt`) for shared client state | SSR-safe stores |
| Validation | Zod (`readValidatedBody`, `getValidatedQuery` in Nitro) | One schema client and server |
| Data access | Drizzle ORM + PostgreSQL (or Prisma) | Typed queries, migrations as files |
| Auth | `nuxt-auth-utils` (sealed cookie sessions) or the provider's module | |
| Styling | Tailwind CSS (`@nuxtjs/tailwindcss`) or Nuxt UI | Tokens in the theme |
| Unit tests | Vitest + `@nuxt/test-utils` + `@vue/test-utils` | |
| E2E tests | Playwright | |
| Lint/format | `@nuxt/eslint` (flat config) + Prettier | |
| Package manager | pnpm | |

## Project layout

```
app.vue
nuxt.config.ts
pages/                             routes only
  index.vue
  orders/index.vue
  orders/[id].vue
layouts/default.vue
middleware/auth.ts                 route guards
components/
  ui/                              primitives (BaseButton.vue, BaseField.vue…)
  orders/OrderTable.vue
  orders/OrderForm.vue
composables/
  useOrders.ts                     useFetch wrappers with typed responses
stores/
  ui.ts                            Pinia store for client-only UI state
shared/
  orders/schemas.ts                Zod schemas used by client and server
server/
  api/orders/index.get.ts          thin handler: validate → use case → response
  api/orders/index.post.ts
  api/orders/[id].get.ts
  domain/orders/order.ts           types and rules (no Nitro, no DB)
  domain/orders/order-repository.ts
  infra/db/schema.ts
  infra/orders/order-repository.drizzle.ts
  app/orders/place-order.ts        one use case per file
  utils/container.ts               wiring of repositories into use cases
tests/e2e/
```

Dependency direction: `pages → components → composables → server/api` (over HTTP) and
`server/api → server/app → server/domain`; `server/infra` implements domain interfaces. Domain imports nothing from Nuxt.

## Conventions

- One file = one responsibility: one component, one composable, one handler per method/route, one use case.
- `<script setup lang="ts">` with `defineProps<…>()` and `defineEmits<…>()`; no Options API.
- Data on pages through `useFetch`/`useAsyncData` with a stable key; never `$fetch` directly in setup for SSR data.
- Server handlers validate with Zod (`readValidatedBody`, `getValidatedQuery`) and throw `createError({ statusCode })` for domain errors in one mapping helper.
- Pinia only for client state no server owns; never cache API data in a store.
- Runtime config through `useRuntimeConfig()`; secrets only in the private part.
- Components PascalCase files, composables `useX.ts`, server routes `name.method.ts`.
- New feature = domain + repository + use case in `server/` → API routes → composable → components → page.

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Dev | `pnpm dev` |
| Build | `pnpm build` |
| Preview | `pnpm preview` |
| Type check | `pnpm nuxi typecheck` |
| Lint | `pnpm lint` |
| Format | `pnpm prettier --write .` |
| Unit tests | `pnpm vitest run` |
| E2E tests | `pnpm playwright test` |
| Migrations | `pnpm drizzle-kit generate && pnpm drizzle-kit migrate` |

## Testing

- Domain and use cases: Vitest with in-memory repositories.
- Server routes: `@nuxt/test-utils` `$fetch` against the test server; assert status codes and validation errors.
- Components: `@vue/test-utils` (`mountSuspended`) for components with logic.
- Playwright for critical flows on a production build.
- A bug fix starts with a failing test.

## Quality gates

- `nuxi typecheck` with zero errors; no `any`.
- ESLint `--max-warnings 0`, Prettier clean.
- Vitest and Playwright green in CI; `nuxi build` succeeds.

## Dependencies

- Nuxt and Vue built-ins first (`useFetch`, `useState`, `useRuntimeConfig`, Nitro utilities).
- Allowed: the table above and official Nuxt modules; anything else needs a reason in the PR.
- Do NOT use: Vuex, Axios (`$fetch`/`useFetch`), Options API in new code, mixins, global event buses, jQuery, client-only data fetching for SSR pages.

## Rules for agents

- Use `<script setup lang="ts">` and the Composition API only.
- Never fetch page data with `$fetch` inside setup; use `useFetch`/`useAsyncData` with a key.
- Every server route validates input with Zod and maps domain errors with `createError`.
- Never put business rules in components or handlers; they live in `server/domain` and `server/app`.
- Never expose secrets in `runtimeConfig.public`.
- Pinia stores hold UI state only; API data stays in the fetch cache.
- Rely on auto-imports consistently; do not mix explicit and auto imports of the same thing.
- Every schema change has a migration; never edit an applied one.
