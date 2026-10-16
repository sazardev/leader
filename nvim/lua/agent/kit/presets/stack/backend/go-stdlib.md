<!-- name: Go stdlib REST -->
<!-- desc: Go 1.25+ REST API with zero HTTP dependencies: net/http ServeMux patterns, database/sql, slog, json -->

# STACK.md: Go stdlib REST

## Summary

A REST API written with the Go standard library only for HTTP, JSON and logging: `net/http`'s `ServeMux` routes by
method and path parameters (Go 1.22+), `encoding/json` encodes, `log/slog` logs, `database/sql` talks to the database
through one driver. The smallest attack and maintenance surface, fast builds, no framework upgrades. Hexagonal layout:
the domain knows nothing about HTTP or SQL.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Go 1.25+ | One static binary, stable standard library |
| HTTP | `net/http` (`ServeMux` with `GET /orders/{id}` patterns, `r.PathValue`) | No router dependency since Go 1.22 |
| JSON | `encoding/json` (`DisallowUnknownFields` on input) | Standard, strict decoding |
| Database | PostgreSQL via `database/sql` + `github.com/jackc/pgx/v5/stdlib`, or SQLite via `modernc.org/sqlite` (pure Go) | One driver, standard interface |
| Queries | Hand-written SQL in the repository files (or `sqlc` generating `database/sql` code) | Explicit SQL, no ORM |
| Migrations | SQL files embedded with `embed` and applied at startup by a ~50-line runner (or `goose`) | No external tool required |
| Config | `os.Getenv` into a typed struct, validated at startup | No config library |
| Logging | `log/slog` (JSON handler in production) | Structured, standard |
| Testing | `testing`, `net/http/httptest`, `testing/synctest` where time matters | Standard library only |
| Lint | golangci-lint v2 | Many linters, one config |
| Deploy | One static binary (`CGO_ENABLED=0`) | See the deploy add-on for the pipeline |

## Project layout

```
cmd/api/main.go                    config → db → repositories → services → routes → server with timeouts + graceful shutdown
internal/
  config/config.go                 typed config from env + Validate()
  platform/
    httpx/respond.go               JSON responses + RFC 9457 problem details
    httpx/decode.go                strict JSON decoding with size limit
    httpx/middleware.go            request id, logging, recover, timeout (one func each)
    database/open.go               sql.Open + pool limits + ping
    database/migrate.go            embedded migrations runner
  orders/
    order.go                       entity + invariants
    errors.go                      ErrNotFound, ErrInvalid…
    repository.go                  port (interface)
    service.go                     use cases
    postgres_repository.go         implements the port with database/sql
    http_handlers.go               handlers: decode → service → respond
    routes.go                      func Routes(mux *http.ServeMux, h *Handlers)
migrations/0001_orders.sql
```

Dependency direction: `http_handlers → service → repository (port) ← postgres_repository`; `cmd/api` is the only place
that wires concrete types. The domain files (`order.go`, `errors.go`, `repository.go`, `service.go`) import only the standard library.

## Conventions

- Routes are registered with method patterns (`mux.HandleFunc("POST /orders", h.create)`); path values via `r.PathValue("id")`.
- The server sets `ReadHeaderTimeout`, `ReadTimeout`, `WriteTimeout`, `IdleTimeout` and `MaxHeaderBytes`; bodies are capped with `http.MaxBytesReader`.
- Errors: wrap with `fmt.Errorf("create order: %w", err)`; map domain errors to status codes in one function (`httpx.Error`), responding with problem details.
- `context.Context` is the first parameter of anything that does IO; handlers pass `r.Context()`.
- `database/sql` pool limits (`SetMaxOpenConns`, `SetMaxIdleConns`, `SetConnMaxLifetime`) are set explicitly; `rows.Close()` and `rows.Err()` always checked.
- Graceful shutdown on SIGINT/SIGTERM with `signal.NotifyContext` and `srv.Shutdown`.
- New endpoint = entity/service method → repository method → handler → route → tests.

## Commands

| Task | Command |
| --- | --- |
| Run | `go run ./cmd/api` |
| Build | `CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o bin/api ./cmd/api` |
| Test | `go test -race ./...` |
| Lint | `golangci-lint run` |
| Format | `gofmt -w .` |
| Vulnerabilities | `govulncheck ./...` |
| Tidy | `go mod tidy` |

## Testing

- Services: table-driven unit tests with an in-memory fake of the repository.
- Repositories: integration tests against a real database (Postgres in a container, or SQLite in a temp file).
- Handlers: `httptest.NewRecorder` with the service faked; assert status, problem-details body and headers.
- The whole server: `httptest.NewServer(routes)` for a few end-to-end flows.
- A bug fix starts with a failing test.

## Quality gates

- `gofmt` clean, `go vet ./...` clean, `golangci-lint run` zero issues (errcheck, staticcheck, gosec, bodyclose, sqlclosecheck, rowserrcheck).
- `go test -race ./...` passes; `govulncheck ./...` reports nothing reachable.
- `go.mod` lists only the database driver (and optionally `goose`/`sqlc` tools): anything else needs a written reason.

## Dependencies

- Standard library first, always. Allowed: one database driver; `golang.org/x/*` packages when the standard library lacks it.
- Do NOT use: routers or web frameworks (chi, gin, echo, fiber), ORMs (GORM, ent), config libraries (viper), logging libraries (zap, logrus), assertion libraries.

## Rules for agents

- Never add a third-party HTTP, routing, logging or config package; use `net/http`, `log/slog` and `os`.
- Every handler limits the body size and decodes JSON strictly.
- Never build SQL with string concatenation; use placeholders.
- Always close `rows` and check `rows.Err()`; always pass the request context to the database.
- Map domain errors to HTTP status codes in one place; never leak internal error text to clients.
- Every server and client has explicit timeouts.
- Keep `cmd/api/main.go` the only place where concrete types are wired.
- Every new route gets a handler test and appears in `routes.go` of its package.
