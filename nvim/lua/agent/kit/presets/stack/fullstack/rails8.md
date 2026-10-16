<!-- name: Rails 8 + Hotwire -->
<!-- desc: Ruby on Rails 8: Hotwire (Turbo + Stimulus), Solid Queue/Cache, SQLite or Postgres, Kamal, Minitest -->

# STACK.md: Rails 8 + Hotwire

## Summary

A server-rendered web application on Ruby on Rails 8. HTML over the wire with Turbo (Drive, Frames, Streams) and small
Stimulus controllers for behaviour; no SPA, no JS build step (importmap + Propshaft). Rails 8's "Solid" trio (Queue,
Cache, Cable) keeps the app on one database; Kamal deploys it to any server. Business rules live in models and plain Ruby
objects, not controllers.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Ruby 3.4 | Expressive, YJIT fast enough |
| Framework | Rails 8.0 | Conventions, batteries included |
| Front-end | Turbo + Stimulus (importmap, Propshaft) | Hypermedia, no bundler |
| CSS | Tailwind via `tailwindcss-rails` or plain CSS | No Node toolchain |
| Data | SQLite (production-ready in Rails 8) or PostgreSQL | One file or one server |
| Jobs / cache / cable | Solid Queue, Solid Cache, Solid Cable | Database-backed, no Redis |
| Auth | Rails 8 authentication generator | Code you own |
| Testing | Minitest + fixtures + system tests (Capybara) | Rails default, fast |
| Lint | RuboCop (`rubocop-rails-omakase`) + Brakeman | Style and security |
| Deploy | Kamal 2 (container, Thruster in front) | Zero-downtime on your own server |

## Project layout

```
app/
  models/
    invoice.rb                 ActiveRecord model: validations, associations, domain methods
    invoice/
      payable.rb               concern: one cohesive behaviour per file
  services/ (only when a use case spans models)
    invoices/issue.rb          plain Ruby object with #call
  controllers/
    invoices_controller.rb     REST actions only, thin
  views/invoices/
    index.html.erb
    _invoice.html.erb          partial = Turbo Frame / Stream target
    create.turbo_stream.erb
  javascript/controllers/
    clipboard_controller.js    one Stimulus controller per behaviour
  jobs/
    send_invoice_job.rb
db/migrate/
test/
  models/invoice_test.rb
  controllers/invoices_controller_test.rb
  system/invoices_test.rb
  fixtures/invoices.yml
config/deploy.yml              Kamal
```

Dependency direction: `controllers → models/services`; views read models, never write; jobs call models or services.

## Conventions

- REST only: seven actions per controller; a new verb is a new resource (`Invoices::PaymentsController#create`).
- Fat models are split into concerns by behaviour; cross-model workflows get a service object with one public method.
- Responses: HTML for full pages, `turbo_stream` for partial updates; same partials for both.
- Stimulus controllers are small, generic and named by behaviour (`toggle`, `clipboard`), not by page.

## Commands

| Task | Command |
| --- | --- |
| Setup | `bin/setup` |
| Dev | `bin/dev` |
| Test | `bin/rails test && bin/rails test:system` |
| Lint | `bin/rubocop` |
| Security | `bin/brakeman` |
| Migrate | `bin/rails db:migrate` |
| Deploy | `bin/kamal deploy` |

## Testing

- Model tests for every validation and domain method; controller tests for status and redirects; a system test per main flow.
- Fixtures over factories; tests run in parallel (`parallelize(workers: :number_of_processors)`).

## Quality gates

- `bin/rubocop` and `bin/brakeman --no-pager` clean; all tests green; `bin/rails db:migrate` reversible (`db:rollback` works).

## Dependencies

- Rails defaults first (Solid Queue/Cache/Cable, importmap, Propshaft). A gem needs a reason in the PR.
- Do NOT use: a JS bundler or SPA framework, Redis/Sidekiq for what Solid Queue does, service objects for single-model logic.

## Rules for agents

- Keep controllers to params, one model/service call and a render/redirect.
- Use strong parameters; never `permit!`.
- Prefer Turbo Streams and Frames over custom JavaScript; add Stimulus only for behaviour HTML can't express.
- Every schema change is a migration; never edit an applied one.
- Avoid N+1: `includes` in queries that render collections (Bullet in development).
- Background work goes to jobs (`perform_later`), never inline in a request.
- Write the model test before the model change.
- Follow Rails naming conventions; no custom folder structure outside `app/`.
