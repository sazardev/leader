<!-- name: Ruby Rails API -->
<!-- desc: Rails 8 API mode: ActiveRecord, Solid Queue, Puma, RSpec -->
<!-- for: backend -->

# STACK.md: Ruby Rails API

## Summary

A JSON API in Ruby. Rails 8 in API mode gives the routing, ActiveRecord, migrations and test doubles; Solid Queue handles background jobs without Redis; Puma serves it. Hexagonal layout by domain: services (use cases) between controllers and models. Everything is tested with RSpec against a real Postgres.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Ruby 3.3+ | Modern syntax, Sorbet types where they pay |
| Packaging | `bundler` (`Gemfile` + `Gemfile.lock`) | Reproducible |
| Framework | Rails 8 API mode + Puma | Routing, ORM, migrations |
| API | ActiveModel serializers + `committee` (OpenAPI) | Contract-first where it pays |
| Database | PostgreSQL 16 | Relational, transactional |
| DB access | ActiveRecord (`where`, `joins`, `transaction`) | Transactions and migrations built in |
| Migrations | `rails generate migration` + `db:migrate` | Forward-only, reviewed by hand |
| Settings | `ENV` → typed `Settings` module | Env → validated at boot |
| Logging | `Rails.logger` (JSON formatter in prod) | Standard |
| Auth | JWT (`jwt`, `BCrypt`) or session cookies | Standard primitives |
| Jobs | Solid Queue | No Redis needed |
| Testing | RSpec + `factory_bot` + `testcontainers` (or Docker Postgres) | Real DB in integration |
| Lint / format | `rubocop` | One tool |

## Project layout

```
Gemfile
config/
  routes.rb                        API routes per namespace
  initializers/
app/
  controllers/api/v1/
    orders_controller.rb           decode → service → encode
  services/orders/place_order.rb   one use case per file
  models/order.rb                  ActiveRecord models + invariants
  serializers/order_serializer.rb
  errors.rb                        DomainError + mapping to HTTP status in ONE place
db/migrate/                        Rails migrations
spec/
  services/orders/                 use cases with doubles / in-memory fakes
  requests/api/v1/                 API against Postgres
  factories/                       factory_bot factories
```

Dependency direction: `controllers → services → models`.

## Conventions

- One service = one use case; services over ~100 lines are split.
- Controllers are thin: params in, one service, JSON out. No ActiveRecord queries in controllers.
- Models hold invariants (validations, scopes); services hold orchestration and transactions.
- N+1 is a bug: `includes`/`eager_load` are the default, checked with Bullet in tests.
- Settings come from the environment; no secrets in code; `.env.example` documents them.

## Commands

| Task | Command |
| --- | --- |
| Install | `bundle install` |
| Dev | `bin/rails server` |
| Test | `bundle exec rspec` |
| Single test | `bundle exec rspec spec/services/orders/place_order_spec.rb` |
| Lint | `bundle exec rubocop` |
| Migrate makemigrations | `bin/rails generate migration CreateOrders` |
| Migrate | `bin/rails db:migrate` |

## Testing

- Services: RSpec unit tests with doubles; no DB.
- Controllers and models: request + integration specs against Postgres; migrations applied once per session.
- Factories for test data (`factory_bot`), no shared hidden state.
- A bug fix starts with a failing spec; services coverage above 85%.

## Quality gates

- `rubocop` with zero offenses.
- `bundle exec rspec` passes in CI; `rails db:migrate:status` reports no pending migrations.
- `bundler-check` passes.

## Dependencies

- Gemfile first; then the table above. Every new gem is added with `bundle add` and justified in the PR.
- Do NOT use: raw SQL in controllers; GraphQL alongside the JSON API without a reason; Redis alongside Solid Queue without a reason.

## Rules for agents

- Change `serializers` and `routes.rb` first for any endpoint change.
- Never put business rules in controllers; they live in services and model invariants.
- Every query goes through ActiveRecord with parameters; never build SQL with string concatenation.
- Never log secrets or full request bodies; log the request id.
- Add a migration for every schema change; never edit an applied migration.
- Run `rubocop` and `rspec` before declaring a change done.
- Add gems only with `bundle add`; never edit `Gemfile.lock` by hand.
