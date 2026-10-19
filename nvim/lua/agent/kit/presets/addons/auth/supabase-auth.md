<!-- name: Supabase Auth -->
<!-- desc: hosted auth from Supabase: email, OAuth and magic links, JWT sessions, Row Level Security on Postgres -->
<!-- for: ts js node flutter !game -->

## Stack

| Auth | Supabase Auth (GoTrue: email, OAuth, magic links; JWT sessions; Row Level Security in Postgres) | Auth and database share one identity, so policies can use `auth.uid()` |

## Project layout

```
supabase/config.toml           local project config (auth providers, redirect URLs)
supabase/migrations/           SQL migrations including every RLS policy
src/lib/supabase/              client factories: browser client and server client with the cookie session
```

## Conventions

- Only the project URL and the anon key reach the client; the `service_role` key lives only on the server and never in a mobile or browser bundle.
- Every table in `public` has RLS enabled and explicit policies (`using (auth.uid() = user_id)`); no table is left without RLS.
- Server code calls `supabase.auth.getUser()` (validated), not `getSession()` alone, before trusting an identity.
- Set the site URL and the allowed redirect URLs per environment.
- Flutter uses `supabase_flutter` and persists the session through its built-in storage.

## Commands

| Local | `supabase start` |
| Types | `supabase gen types typescript --local > src/lib/database.types.ts` |

## Testing

- Policies are tested with pgTAP (`supabase test db`) for each role: owner, other user, anonymous.

## Rules for agents

- Never ship the `service_role` key to a client or commit it.
- Never create a table without RLS and its policies in the same migration.
- Never use `getSession()` alone on the server to authorize an action.
