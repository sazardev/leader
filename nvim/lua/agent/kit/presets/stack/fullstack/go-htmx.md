<!-- name: Go + templ + htmx -->
<!-- desc: server-rendered web app: Go, chi, templ, htmx, Postgres (pgx + sqlc), Tailwind; one binary -->

# STACK.md: Go + templ + htmx

## Summary

A server-rendered web application in one Go binary: HTML is rendered with templ, interactivity comes from htmx swapping
HTML fragments (hypermedia, no JSON API for the UI, no SPA build). Hexagonal layout: the domain knows nothing about HTTP,
SQL or templates; handlers and repositories are adapters around it.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Go 1.23+ | Simple, fast to compile, one static binary, great standard library |
| HTTP router | `go-chi/chi/v5` | `net/http` compatible, middlewares, route groups; nothing magic |
| Templates | `a-h/templ` | Type-checked components compiled to Go; no runtime template errors |
| Interactivity | htmx 2 (+ Alpine.js only for local UI state) | Hypermedia: the server stays the source of truth |
| CSS | Tailwind CSS (standalone CLI, no Node) | Utility classes inside templ components; tokens in the config |
| Database | PostgreSQL 16 | Relational, transactional, mature |
| DB access | `jackc/pgx/v5` + `sqlc` | SQL written by hand, Go code generated and type-safe; no ORM |
| Migrations | `pressly/goose` | Plain SQL files, up/down, embedded in the binary |
| Config | env vars → typed struct (`caarlos0/env`) | 12-factor; validated at startup |
| Logging | `log/slog` (JSON in prod) | Standard library, structured |
| Sessions/auth | `alexedwards/scs` + bcrypt/argon2id | Server-side sessions; CSRF with `gorilla/csrf` or `justinas/nosurf` |
| Testing | `testing` + `testify/require` (optional) + testcontainers-go | Real Postgres in integration tests |
| Live reload | `air` + `templ generate --watch` | Fast edit loop |
| Lint | golangci-lint v2 | One config, many linters |
| Deploy | Distroless container or the binary + systemd | Static assets embedded with `embed` |

## Project layout

```
cmd/web/main.go                 wiring only: config, DB pool, repositories, services, router, server
internal/
  config/config.go              typed env config + validation
  domain/<context>/             entities, value objects, domain errors, ports (interfaces) — no imports of adapters
    order.go                    Order entity + its invariants
    order_status.go             value object
    errors.go                   ErrNotFound, ErrInvalidTransition…
    repository.go               OrderRepository port
  app/<context>/                use cases: one file per use case (place_order.go, cancel_order.go)
  adapters/
    postgres/<context>_repo.go  implements the domain port with sqlc queries
    postgres/queries/*.sql      sqlc input
    postgres/db/                sqlc output (generated, never edited)
    http/
      router.go                 routes and middleware stack
      middleware/               one middleware per file
      <context>/handler.go      HTTP → use case → view; parses input, maps errors to status codes
  views/
    layouts/base.templ          <html>, head, nav
    components/                 reusable templ components (button.templ, field.templ, table.templ)
    pages/<context>/            full pages and the fragments htmx swaps
migrations/                     goose SQL migrations (0001_create_orders.sql)
static/                         compiled CSS, htmx.min.js, images (embedded)
```

Dependency direction: `adapters → app → domain`. `domain` imports only the standard library. `views` never import `adapters`.

## Conventions

- One file = one responsibility: one entity, one use case, one handler group, one component. Files over ~300 lines are split.
- Handlers are thin: parse and validate input, call one use case, render one view. No SQL, no business rules.
- A request with `HX-Request: true` gets the fragment; a normal request gets the full page (same handler, `render(w, r, page, fragment)`).
- Forms post back to the same URL; validation errors re-render the form fragment with `422`.
- Errors: wrap with `fmt.Errorf("place order: %w", err)`; map domain errors to HTTP status in ONE place (`http/errors.go`).
- `context.Context` is the first parameter of anything that does IO.
- Constructors `NewX(deps…) *X` with explicit dependencies; no globals, no `init()` side effects.
- New feature = domain types + port → use case → repository (sqlc query) → handler → templ page/fragments → route.

## Commands

| Task | Command |
| --- | --- |
| Dev (live reload) | `air` (runs `templ generate` and Tailwind watch) |
| Generate | `templ generate && sqlc generate` |
| Build | `go build -o bin/web ./cmd/web` |
| Test | `go test ./...` |
| Integration tests | `go test -tags=integration ./...` |
| Lint | `golangci-lint run` |
| Format | `gofmt -w . && templ fmt .` |
| Migrate | `goose -dir migrations postgres "$DATABASE_URL" up` |

## Testing

- Domain and use cases: plain unit tests with in-memory fakes of the ports (table-driven).
- Repositories: integration tests against a real Postgres (testcontainers), each test in a transaction rolled back.
- Handlers: `httptest` with the use case faked; assert status, `HX-*` headers and key HTML fragments (not whole pages).
- templ components: render to a buffer and assert on the output for components with logic.
- A bug fix starts with a failing test.

## Quality gates

- `gofmt`/`templ fmt` clean, `golangci-lint run` with zero issues (errcheck, govet, staticcheck, gosec, revive, gocritic enabled).
- `go test -race ./...` passes; generated code (`templ generate`, `sqlc generate`) is committed and up to date (CI diffs it).
- `go vet` and `go mod tidy` leave no changes.

## Dependencies

- Standard library first (`net/http`, `log/slog`, `encoding/json`, `embed`, `errors`).
- Allowed: the table above. Anything else needs a reason in the PR.
- Do NOT use: ORMs (GORM, ent) — sqlc keeps SQL explicit; heavy web frameworks (Gin/Echo/Fiber) — chi is enough; a JS framework or bundler for the UI.

## Rules for agents

- Never put business rules in handlers, templates or SQL; they live in `domain` and `app`.
- Never edit files under `adapters/postgres/db/` or `*_templ.go`: change the `.sql` or `.templ` and regenerate.
- Every new query goes through sqlc; never build SQL with string concatenation.
- Return fragments for htmx requests; set `HX-Trigger` for cross-component updates instead of extra requests.
- Every form has CSRF protection and server-side validation, even with client-side hints.
- Escape nothing by hand: templ escapes; `templ.Raw` only with sanitized input and a comment saying why.
- Add a migration for every schema change; never edit an applied migration.
- Keep `cmd/web/main.go` as the only place where concrete types are wired together.
