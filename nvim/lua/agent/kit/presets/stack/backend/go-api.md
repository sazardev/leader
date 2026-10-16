<!-- name: Go REST API -->
<!-- desc: JSON API in Go: net/http 1.22 routing (or chi), pgx + sqlc, goose, slog, OpenAPI, testcontainers -->

# STACK.md: Go REST API

## Summary

A JSON HTTP API in one Go binary. Hexagonal layout: the domain and the use cases know nothing about HTTP, JSON or SQL;
HTTP handlers and Postgres repositories are adapters wired together in `main`. The OpenAPI document is the contract
with clients and is kept in the repository next to the code that serves it.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Go 1.23+ | One static binary, fast builds, strong standard library |
| HTTP routing | `net/http` `ServeMux` (Go 1.22 patterns: `GET /orders/{id}`) or `go-chi/chi/v5` | Standard library first; chi when route groups and middleware stacks grow |
| API contract | OpenAPI 3.1 in `api/openapi.yaml` + `oapi-codegen` (strict server, types) | Contract-first: request/response types generated, never drift |
| Validation | Generated types + explicit `Validate()` on input DTOs | Errors returned as RFC 9457 problem details |
| Database | PostgreSQL 16 | Relational, transactional, mature |
| DB access | `jackc/pgx/v5` (`pgxpool`) + `sqlc` | Hand-written SQL, generated type-safe Go; no ORM |
| Migrations | `pressly/goose/v3` | Plain SQL up/down files, embedded with `embed` |
| Config | env vars → typed struct (`caarlos0/env/v11`) | 12-factor, validated at startup |
| Logging | `log/slog` (JSON handler in prod) | Structured, standard library |
| Observability | OpenTelemetry (`otelhttp`, `otelpgx`) + Prometheus metrics | Traces per request, RED metrics |
| Auth | JWT verification (`lestrrat-go/jwx/v2`) or opaque session tokens | Verified in a middleware, identity passed in `context` |
| Testing | `testing` + `stretchr/testify/require` + `testcontainers-go` | Real Postgres in integration tests |
| Lint | golangci-lint v2 | One config, many linters |
| Deploy | Distroless container (`gcr.io/distroless/static`) | Small, no shell |

## Project layout

```
cmd/api/main.go                    composition root: config, pool, repositories, services, router, server, graceful shutdown
api/openapi.yaml                   the contract (source of truth for routes and payloads)
internal/
  config/config.go                 typed env config + validation
  domain/<context>/                entities, value objects, domain errors, ports — standard library only
    order.go                       Order entity and its invariants
    status.go                      value object
    errors.go                      ErrNotFound, ErrConflict, ErrInvalidTransition
    repository.go                  OrderRepository port (interface owned by the domain)
  app/<context>/                   use cases: one file per use case
    place_order.go                 PlaceOrder struct + Execute(ctx, input) (output, error)
    place_order_test.go            unit test with in-memory fakes
  adapters/
    postgres/<context>_repo.go     implements the domain port with sqlc queries
    postgres/queries/*.sql         sqlc input
    postgres/db/                   sqlc output (generated, never edited)
    postgres/tx.go                 transaction helper (unit of work)
    http/
      server.go                    http.Server with timeouts
      router.go                    routes and middleware order
      middleware/                  one middleware per file (requestid.go, recover.go, auth.go, logging.go)
      problem.go                   domain error → RFC 9457 problem + status, in ONE place
      <context>/handler.go         decode → use case → encode; implements the generated strict interface
      gen/                         oapi-codegen output (generated)
migrations/                        goose SQL migrations (00001_create_orders.sql)
```

Dependency direction: `adapters → app → domain`. `domain` imports nothing outside the standard library; `app` imports only `domain`.

## Conventions

- One file = one responsibility: one entity, one use case, one handler group, one middleware. Files over ~300 lines are split.
- Handlers are thin: decode and validate, call one use case, encode the response. No SQL, no business rules.
- Errors: wrap with `fmt.Errorf("place order: %w", err)`; compare with `errors.Is/As`; map to HTTP status only in `problem.go`.
- `context.Context` is the first parameter of anything that does IO; never stored in structs.
- Constructors `NewX(deps…) *X` with explicit dependencies; no package-level state, no `init()` side effects.
- Every `http.Server` has `ReadHeaderTimeout`, `ReadTimeout`, `WriteTimeout`, `IdleTimeout`; every outgoing call has a deadline.
- JSON fields are `snake_case` or `camelCase` as the contract says, decided once; times in RFC 3339 UTC; money as integer minor units.
- Pagination is cursor-based (`?cursor=&limit=`), with a maximum limit enforced server-side.
- New endpoint = contract in `openapi.yaml` → `go generate` → domain/port changes → use case + test → sqlc query → repository → handler → route.

## Commands

| Task | Command |
| --- | --- |
| Run | `go run ./cmd/api` (or `air` for live reload) |
| Generate | `go generate ./... && sqlc generate` |
| Build | `CGO_ENABLED=0 go build -o bin/api ./cmd/api` |
| Test | `go test -race ./...` |
| Integration tests | `go test -race -tags=integration ./...` |
| Single test | `go test -run TestPlaceOrder ./internal/app/order/` |
| Lint | `golangci-lint run` |
| Format | `gofmt -w . && goimports -w .` |
| Migrate | `goose -dir migrations postgres "$DATABASE_URL" up` |

## Testing

- Domain and use cases: table-driven unit tests with in-memory fakes of the ports; no mocks framework needed.
- Repositories: integration tests (`//go:build integration`) against Postgres in testcontainers; migrations applied once, each test in a rolled-back transaction.
- Handlers: `httptest.NewRecorder` with the use case faked; assert status, headers and the JSON body against the contract types.
- Contract: a test loads `openapi.yaml` and checks every route is registered (and no unregistered route exists).
- A bug fix starts with a failing test; coverage of `domain` and `app` stays above 80%.

## Quality gates

- `gofmt`/`goimports` clean; `golangci-lint run` with zero issues (errcheck, govet, staticcheck, gosec, revive, gocritic, bodyclose, contextcheck, noctx).
- `go test -race ./...` and integration tests pass in CI.
- Generated code (oapi-codegen, sqlc) is committed and up to date: CI regenerates and fails on a diff.
- `go mod tidy` and `go vet ./...` leave no changes; `govulncheck ./...` reports nothing.

## Dependencies

- Standard library first (`net/http`, `encoding/json`, `log/slog`, `errors`, `embed`, `context`).
- Allowed: the table above. Anything else needs a reason in the PR (what the standard library lacks).
- Do NOT use: ORMs (GORM, ent) — sqlc keeps SQL explicit; heavy frameworks (Gin, Echo, Fiber, Beego) — `net/http` is enough; `logrus`/`zap` — slog is standard; global mocks generators for every interface — write small fakes.

## Rules for agents

- Change `api/openapi.yaml` first for any endpoint change, then regenerate; never hand-edit `gen/` or `postgres/db/`.
- Never put business rules in handlers or SQL; they live in `domain` (invariants) and `app` (orchestration).
- Every query goes through sqlc with parameters; never build SQL with string concatenation.
- Map errors to status codes only in `problem.go`; never write `http.Error` with a raw `err.Error()` (leaks internals).
- Never log secrets, tokens, passwords or full request bodies; log the request id.
- Writes that touch several tables run in one transaction through the unit-of-work helper.
- Add a migration for every schema change; never edit an applied migration; every migration has a down.
- Keep `cmd/api/main.go` as the only place where concrete types are wired together.
- Every new use case ships with its unit test; every new repository method with an integration test.
