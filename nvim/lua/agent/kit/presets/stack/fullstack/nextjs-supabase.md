<!-- name: Next.js + Supabase -->
<!-- desc: Next.js App Router + Supabase: Postgres with RLS as the security boundary, Auth, generated types -->

# STACK.md: Next.js + Supabase

## Summary

A full-stack application on Next.js (App Router) with Supabase as the backend: Postgres, Auth, Storage and Realtime.
Row Level Security policies in Postgres are the security boundary: every table has RLS on, and the app talks to the
database with the user's session, so a bug in the UI cannot leak another user's rows. Schema changes are SQL migrations
managed by the Supabase CLI, and TypeScript types are generated from the database.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript 7 (native `tsc`, `strict`) | |
| Framework | Next.js 15 (App Router), React 19 | Server Components, Server Actions |
| Backend | Supabase (Postgres 15+, Auth, Storage, Realtime) | Managed Postgres with auth and policies |
| Supabase client | `@supabase/ssr` + `@supabase/supabase-js` | Cookie sessions for server and browser clients |
| Types | `supabase gen types typescript` → `database.types.ts` | Queries typed from the real schema |
| Security | RLS policies on every table; `security definer` functions only when reviewed | Authorization in the database |
| Validation | Zod | Action and form input |
| Styling | Tailwind CSS 4 + shadcn/ui | |
| Local dev | Supabase CLI (`supabase start`, Docker) | The whole backend locally |
| Unit tests | Vitest | |
| DB tests | pgTAP (`supabase test db`) | RLS policies tested in SQL |
| E2E tests | Playwright | |
| Lint/format | ESLint + Prettier; `supabase db lint` | |
| Package manager | pnpm | |

## Project layout

```
src/
  app/                               routes only
    (auth)/login/page.tsx
    (app)/layout.tsx                 redirects when there is no user
    (app)/projects/page.tsx
    auth/callback/route.ts           exchanges the auth code for a session
  middleware.ts                      refreshes the session cookie (updateSession)
  features/
    projects/
      domain/project.ts              types and pure rules
      queries.ts                     server-only reads through the server client
      actions.ts                     "use server": Zod → repository → revalidatePath
      repository.ts                  ProjectRepository interface
      repository.supabase.ts         implementation with the typed client
      schemas.ts
      components/project-list.tsx
      components/project-form.tsx    "use client"
  lib/supabase/
    server.ts                        createServerClient (cookies)
    client.ts                        createBrowserClient
    middleware.ts                    updateSession helper
    database.types.ts                generated, never edited
  components/ui/                     shadcn/ui primitives
supabase/
  config.toml
  migrations/20250110120000_create_projects.sql   tables, indexes, RLS policies
  seed.sql
  tests/projects_rls.test.sql        pgTAP
tests/e2e/
```

Dependency direction: `app → features/*/components → features/*/{actions,queries} → repository interface → domain`;
only `repository.supabase.ts` and `lib/supabase` import the Supabase client.

## Conventions

- Every table is created with `alter table … enable row level security` and explicit policies per operation (`select`, `insert`, `update`, `delete`) in the same migration.
- Policies use `(select auth.uid())` and indexed columns (`owner_id`, `org_id`); membership checks go through `security definer` functions with a fixed `search_path`.
- The app uses the user's session client; the `service_role` key is used only in server-side jobs/webhooks, never in request handlers that act for a user.
- One file = one responsibility; files over ~250 lines are split.
- Server Actions validate with Zod and return typed results; they rely on RLS, and also check the obvious (signed in).
- Regenerate types after every migration; code uses `Tables<'projects'>` types, never hand-written row types.
- New feature = migration (table + RLS + pgTAP test) → types → repository → queries/actions → components → route.

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Local backend | `supabase start` |
| Dev | `pnpm dev` |
| New migration | `supabase migration new <name>` |
| Apply locally | `supabase db reset` |
| Generate types | `supabase gen types typescript --local > src/lib/supabase/database.types.ts` |
| DB tests | `supabase test db` |
| Lint DB | `supabase db lint` |
| Unit tests | `pnpm vitest run` |
| E2E tests | `pnpm playwright test` |
| Deploy migrations | `supabase db push` |

## Testing

- RLS: pgTAP tests per table: a user sees and changes only their rows, another user gets nothing, anon gets nothing.
- Domain and actions: Vitest with the repository faked.
- Repositories: integration tests against the local Supabase.
- Playwright for sign-in and critical flows against the local stack with `seed.sql` data.

## Quality gates

- `tsc --noEmit`, ESLint `--max-warnings 0`, Prettier clean.
- `supabase db lint` clean; Supabase advisors (security and performance) show no errors.
- Generated types committed and up to date (CI regenerates and diffs).
- pgTAP, Vitest and Playwright green in CI.

## Dependencies

- Supabase and Next.js built-ins first.
- Allowed: the table above; anything else needs a reason in the PR.
- Do NOT use: `@supabase/auth-helpers-nextjs` (replaced by `@supabase/ssr`), an ORM on top of the Supabase client for user requests (it bypasses RLS with a privileged connection), the service role key in the browser or in `NEXT_PUBLIC_` variables, client-side-only auth checks.

## Rules for agents

- Never create a table without enabling RLS and writing its policies in the same migration.
- Never use the `service_role` key in code that runs for a user request or in the browser.
- Never edit an applied migration; create a new one. Never edit `database.types.ts` by hand.
- Use `supabase.auth.getUser()` on the server to trust the user, not `getSession()`.
- Every new policy gets a pgTAP test proving another user cannot read or write.
- `security definer` functions set `search_path = ''` and are reviewed like public API.
- Add indexes for the columns policies filter on.
- Keep Supabase calls inside repositories; components and actions never call `supabase.from` directly.
