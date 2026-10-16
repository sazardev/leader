<!-- name: Elixir + Phoenix API -->
<!-- desc: JSON API on the BEAM: Phoenix, contexts as boundaries, Ecto + Postgres, ExUnit, Credo, Dialyzer -->

# STACK.md: Elixir + Phoenix API

## Summary

A JSON API on Elixir and Phoenix. Business logic lives in **contexts** (plain modules that own a slice of the domain and
its Ecto schemas); controllers are thin adapters that call one context function and render JSON. The BEAM gives
supervision, concurrency and fault isolation for free; background work runs in supervised processes or Oban jobs.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Elixir 1.18+ on Erlang/OTP 27 | Immutable data, pattern matching, supervision trees |
| Web | Phoenix 1.7+ (JSON only, `--no-html --no-assets`) | Mature, fast, plug pipelines |
| Data | PostgreSQL 16 + Ecto 3 (`ecto_sql`, `postgrex`) | Changesets validate at the boundary, migrations as code |
| Jobs | Oban | Postgres-backed, retries, uniqueness, observable |
| Auth | `phx.gen.auth`-style tokens or Guardian-free bearer tokens | Code you own and read |
| Config | `config/runtime.exs` from env vars | 12-factor, read at boot |
| Testing | ExUnit + `Ecto.Adapters.SQL.Sandbox` + `Phoenix.ConnTest` | Parallel DB tests |
| Lint | Credo (strict) + `mix format` | Consistent, idiomatic code |
| Types | Dialyzer via `dialyxir` | Catches contract errors |
| Deploy | Mix release in a container | One artifact, `bin/app start` |

## Project layout

```
lib/
  app/                         the core: contexts, no web
    accounts.ex                Accounts context: public API of the slice
    accounts/
      user.ex                  Ecto schema + changesets
      user_token.ex
    billing.ex                 Billing context
    billing/
      invoice.ex
      invoice_query.ex         composable Ecto queries
    repo.ex
    application.ex             supervision tree
  app_web/                     the HTTP adapter
    router.ex
    endpoint.ex
    controllers/
      invoice_controller.ex    one controller per resource
      invoice_json.ex          rendering only
      fallback_controller.ex   {:error, …} → HTTP status, in one place
    plugs/
      require_auth.ex
priv/repo/migrations/
test/
  app/billing_test.exs         context tests
  app_web/controllers/invoice_controller_test.exs
  support/{conn_case,data_case,fixtures}.ex
```

Dependency direction: `app_web → app`. Contexts never call each other's schemas directly: they call the other context's
public functions. `app` never references `AppWeb`.

## Conventions

- One context per bounded area; its module is the only public entry. Schemas and queries are internal.
- Context functions return `{:ok, value}` / `{:error, %Ecto.Changeset{} | atom}`; controllers use `with` and the
  fallback controller maps errors to status codes.
- Validation lives in changesets; never trust params outside a changeset.
- No processes for code organisation: GenServers only for state or concurrency that needs them.
- New feature = migration → schema + changeset → context function + test → controller + JSON view + route.

## Commands

| Task | Command |
| --- | --- |
| Install | `mix deps.get` |
| Setup DB | `mix ecto.setup` |
| Run | `mix phx.server` |
| Test | `mix test` |
| Format | `mix format` |
| Lint | `mix credo --strict` |
| Types | `mix dialyzer` |
| Migrate | `mix ecto.migrate` |
| Release | `MIX_ENV=prod mix release` |

## Testing

- Context tests (DataCase) cover every rule and error path; controller tests (ConnCase) cover status codes and JSON shape.
- Async tests by default with the SQL sandbox; fixtures through functions in `test/support/fixtures.ex`, not factories with magic.
- Oban jobs tested with `Oban.Testing` (`perform_job/2`).

## Quality gates

- `mix format --check-formatted`, `mix credo --strict` and `mix dialyzer` clean; `mix test --warnings-as-errors` passes.
- `mix compile --warnings-as-errors`; no unused dependencies (`mix deps.unlock --check-unused`).

## Dependencies

- Phoenix, Ecto, Oban, Jason, and test/lint tooling. Anything else needs a reason in the PR.
- Do NOT use: umbrella apps for a single service, GenServers as a code-organisation tool, `Ecto.Repo` calls from controllers.

## Rules for agents

- Controllers call exactly one context function per action; no `Repo` in `app_web`.
- Every input passes through a changeset; never `Repo.insert!` with raw params.
- Return tagged tuples from contexts; map errors to HTTP only in the fallback controller.
- Write the migration with `mix ecto.gen.migration`; never edit an applied migration.
- Add `@spec` to public context functions; keep Dialyzer green.
- Pattern-match in function heads instead of nested `case`/`if`.
- Background work goes to Oban, not `Task.start`.
- Keep modules under ~300 lines: split queries into `*_query.ex` modules.
