<!-- name: Flutter + Supabase -->
<!-- desc: Flutter + supabase_flutter: Auth, Postgres with RLS, Realtime, Storage, Edge Functions, Riverpod -->

# STACK.md: Flutter + Supabase

## Summary

A Flutter app backed by Supabase: Postgres is the database AND the security boundary (Row Level Security policies decide
who reads and writes what), Supabase Auth issues the sessions, Storage holds files and Edge Functions (Deno/TypeScript)
run the logic that must not live on the device (payments, webhooks, secrets). The app talks to Supabase only through
repositories, so the domain never sees the SDK. Schema, policies and functions live in `supabase/` as code.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Dart 3.5+ | Sound null safety, sealed classes, patterns |
| Framework | Flutter (stable channel) | One codebase for Android and iOS (and web) |
| Backend | Supabase (Postgres 15+, Auth, Storage, Realtime, Edge Functions) | Managed Postgres with auth and RLS; self-hostable |
| Client | `supabase_flutter` | Auth session persistence, queries, Realtime, Storage |
| Security | Row Level Security on every table + policies in migrations | The anon key is public: RLS is the only real guard |
| Server logic | Supabase Edge Functions (Deno + TypeScript) | Secrets and privileged work off the device |
| State | `flutter_riverpod` + `riverpod_generator` | Async providers, overrides in tests |
| Navigation | `go_router` with redirects on auth state | Signed-out users never reach private routes |
| Models | `freezed` + `json_serializable` | Immutable entities and DTOs |
| Types | `supabase gen types` (TypeScript for functions) + Dart DTOs kept in sync | One schema, typed both sides |
| Lint | `very_good_analysis`; `deno lint` for functions | Strict analysis on both sides |
| Testing | `flutter_test`, `mocktail`; `supabase start` + pgTAP for policies | RLS is tested, not assumed |
| Deploy | `supabase db push` + `supabase functions deploy`; store builds for the app | See the deploy add-on for the pipeline |

## Project layout

```
lib/
  main.dart                              Supabase.initialize(url, anonKey from --dart-define) → ProviderScope
  app/
    app.dart                             MaterialApp.router, theme, localization
    router.dart                          go_router; redirect reads the auth state provider
  core/
    supabase/supabase_client_provider.dart   the one place that exposes SupabaseClient
    error/failure.dart                   sealed Failure; maps PostgrestException/AuthException
  features/
    auth/
      data/auth_repository.dart          signIn/signUp/signOut/session stream over supabase.auth
      presentation/sign_in_page.dart
    projects/
      domain/project.dart                entity (freezed)
      domain/projects_repository.dart    abstract interface class
      data/project_dto.dart              row ↔ entity
      data/supabase_projects_repository.dart   queries, Realtime channel, Storage uploads
      presentation/projects_controller.dart    @riverpod AsyncNotifier
      presentation/projects_page.dart
supabase/
  config.toml                            local stack config
  migrations/20260101000000_projects.sql tables, indexes, RLS enable + policies (one migration per change)
  seed.sql                               local test data
  functions/
    invite-member/index.ts               one Edge Function per folder
    _shared/cors.ts                      shared helpers
  tests/projects_rls.test.sql            pgTAP tests for the policies
test/                                    mirrors lib/
```

Dependency direction: `presentation → domain ← data`. Only `data/` and `core/supabase/` import `supabase_flutter`.
Edge Functions never import app code; the contract between them is the database schema and JSON bodies.

## Conventions

- Every table has `alter table … enable row level security` and explicit policies in the SAME migration that creates it; policies use `auth.uid()` and are named by intent (`members can read their projects`).
- The app uses only the anon key. The service-role key exists only as an Edge Function secret, never in the app or the repo.
- Schema changes are migrations created with `supabase migration new <name>`; the dashboard is never used to change schema in production.
- Repositories map `PostgrestException`/`AuthException`/`StorageException` to `Failure`s; the UI never shows raw SDK errors.
- Realtime subscriptions are opened in a provider and closed in `ref.onDispose`.
- Storage paths start with the owner's id (`<uid>/<file>`) so storage policies can check them.
- Config (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) comes from `--dart-define-from-file`, one file per flavor, git-ignored when it holds real values.

## Commands

| Task | Command |
| --- | --- |
| Install | `flutter pub get` |
| Local backend | `supabase start` (Docker) |
| New migration | `supabase migration new add_projects` |
| Reset local DB | `supabase db reset` (migrations + seed) |
| Generate types | `supabase gen types typescript --local > supabase/functions/_shared/database.types.ts` |
| Test policies | `supabase test db` |
| Serve functions | `supabase functions serve` |
| Run app | `flutter run --dart-define-from-file=env/dev.json` |
| Generate | `dart run build_runner build --delete-conflicting-outputs` |
| Test | `flutter test` |
| Lint | `flutter analyze && deno lint supabase/functions` |
| Format | `dart format . && deno fmt supabase/functions` |

## Testing

- RLS policies: pgTAP tests per table: who can select/insert/update/delete, as anon, as owner, as another user.
- Repositories: unit tests against a mocked client for mapping, plus integration tests against `supabase start` for real queries.
- Controllers: Riverpod `ProviderContainer` with the repository overridden by a fake.
- Edge Functions: `deno test` with the request built by hand; external APIs mocked.
- Widget and golden tests for key screens; a bug fix starts with a failing test.

## Quality gates

- `flutter analyze` zero issues, `dart format --set-exit-if-changed .`, `deno lint`, `deno fmt --check`.
- `supabase db reset` applies every migration from scratch and `supabase test db` passes.
- `supabase db diff` against the local database shows no drift (schema only changes through migrations).
- `flutter test` passes; generated code is up to date.

## Dependencies

- Allowed: the table above; Deno std and `npm:` specifiers in Edge Functions only when needed.
- Do NOT use: the service-role key in the app, a second backend for what RLS and an Edge Function can do, Firebase alongside Supabase, `http` next to the Supabase client, schema edits through the dashboard in production.

## Rules for agents

- Never create a table without enabling RLS and writing its policies in the same migration.
- Never put the service-role key, or any secret, in Dart code, `--dart-define` files that are committed, or the repo.
- Never edit an applied migration: add a new one.
- Every new policy gets a pgTAP test for both the allowed and the denied case.
- Only `data/` and `core/supabase/` may import `supabase_flutter`.
- Privileged operations (payments, emails, admin actions) go in an Edge Function that checks the caller's JWT.
- Close Realtime channels and stream subscriptions on dispose.
- Regenerate types after every schema change and update the Dart DTOs in the same change.
- Every screen handles loading, error (with retry) and empty states, including the signed-out state.
