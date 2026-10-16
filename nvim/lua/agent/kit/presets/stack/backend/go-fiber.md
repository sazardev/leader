<!-- name: Go + Fiber -->
<!-- desc: Go Fiber on fasthttp for raw throughput: pgx, sqlc, slog; with its caveats (not net/http, ctx reuse) -->

# STACK.md: Go + Fiber

## Summary

A REST API on Fiber, an Express-style framework built on fasthttp, chosen when raw requests per second and low
allocations matter more than `net/http` compatibility. The price is real: Fiber handlers are not `http.Handler`, most of
the `net/http` middleware ecosystem does not plug in, and `*fiber.Ctx` and the values it returns are reused after the
handler returns. Hexagonal layout keeps Fiber at the edge, so the domain could move to `net/http` without changes.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Go 1.25+ | Fast, one static binary |
| HTTP | `github.com/gofiber/fiber/v2` (or v3 once your middleware supports it) on fasthttp | High throughput, low allocations |
| Validation | `github.com/go-playground/validator/v10` | Struct tags, one validator instance |
| Database | PostgreSQL 16 | Relational, transactional |
| DB access | `jackc/pgx/v5` (pgxpool) + `sqlc` | Hand-written SQL, generated type-safe code |
| Migrations | `pressly/goose/v3` | Plain SQL, embedded |
| Config | env → typed struct (`caarlos0/env/v11`) | Validated at startup |
| Logging | `log/slog` (JSON) via a small Fiber middleware | Standard, structured |
| Testing | `testing`, `app.Test(req)`, `testcontainers-go` | In-process requests, real Postgres |
| Load testing | `k6` or `oha` | Throughput is the reason for this stack: measure it |
| Lint | golangci-lint v2 | One config |
| Deploy | Static binary or minimal container | See the deploy add-on for the pipeline |

## Project layout

```
cmd/api/main.go                     config → pgxpool → repos → services → fiber.App → Listen + graceful shutdown
internal/
  config/config.go
  httpapi/
    app.go                          fiber.New(Config{…}) with timeouts, body limit, ErrorHandler
    errors.go                       domain error → status + problem details (the Fiber ErrorHandler)
    middleware/requestid.go         one middleware per file (requestid, logger, recover, limiter)
    orders/handlers.go              parse → validate → service → JSON; copies values it keeps
    orders/routes.go                func Register(r fiber.Router, h *Handlers)
  orders/
    order.go                        entity + invariants (no Fiber import)
    repository.go                   port
    service.go                      use cases
  postgres/
    orders_repository.go            implements the port with sqlc
    queries/orders.sql
    db/                             sqlc output (generated)
migrations/
loadtest/orders.js                  k6 scenario with thresholds
```

Dependency direction: `httpapi → orders (service, ports) ← postgres`. Only `internal/httpapi` and `cmd/api` import Fiber.

## Conventions

- Values from `c.Params`, `c.Query`, `c.Body`, `c.Get` are only valid during the handler: copy them (`utils.CopyString`, `bytes.Clone`) before storing or passing to goroutines; or enable `Immutable: true` and accept the cost.
- Never use `*fiber.Ctx` after the handler returns or inside a goroutine; pass `c.UserContext()` (a `context.Context`) to services.
- `fiber.Config` sets `ReadTimeout`, `WriteTimeout`, `IdleTimeout`, `BodyLimit` and a custom `ErrorHandler` that renders problem details.
- Handlers return errors; the single `ErrorHandler` maps domain errors to status codes.
- One validator instance, created at startup; DTO structs live next to their handlers.
- Graceful shutdown with `app.ShutdownWithContext` on SIGINT/SIGTERM.
- Performance claims come with a k6 run; regressions in p95 or allocations block the change.

## Commands

| Task | Command |
| --- | --- |
| Run | `go run ./cmd/api` |
| Generate | `sqlc generate` |
| Build | `CGO_ENABLED=0 go build -trimpath -o bin/api ./cmd/api` |
| Test | `go test -race ./...` |
| Benchmarks | `go test -bench=. -benchmem ./internal/...` |
| Load test | `k6 run loadtest/orders.js` |
| Lint | `golangci-lint run` |
| Format | `gofmt -w .` |
| Migrate | `goose -dir migrations postgres "$DATABASE_URL" up` |

## Testing

- Services: table-driven unit tests with in-memory fakes of the ports.
- Handlers: `app.Test(httptest.NewRequest(...))` with services faked; assert status, body and headers.
- A regression test that stores a param after the handler returns (catches missing copies).
- Repositories: integration tests against Postgres (testcontainers).
- Hot paths have `Benchmark…` tests with `-benchmem`; load tests have thresholds (p95, error rate).

## Quality gates

- `gofmt`, `go vet`, `golangci-lint run` zero issues; `go test -race ./...` passes.
- sqlc output is up to date (CI diffs it); `govulncheck ./...` clean.
- k6 thresholds pass in CI for the main endpoints.

## Dependencies

- Allowed: the table above; Fiber's own middleware (`fiber/v2/middleware/*`).
- Do NOT use: `net/http` middleware through adaptors in hot paths (it loses the performance this stack is for), ORMs, global `*fiber.Ctx` helpers, a second router.

## Rules for agents

- Never keep or pass to a goroutine any string or byte slice from `*fiber.Ctx` without copying it.
- Never use `*fiber.Ctx` outside the handler; services receive `context.Context`.
- Never import Fiber outside `internal/httpapi` and `cmd/api`.
- Errors go back to the single `ErrorHandler`; handlers do not write error responses themselves.
- Every query goes through sqlc; never concatenate SQL.
- Validate every request DTO with the shared validator before calling a service.
- A change that claims a speedup includes a benchmark or k6 result before and after.
- Keep allocations low on hot paths: no `fmt.Sprintf` in loops, reuse buffers, prefer `strconv`.
