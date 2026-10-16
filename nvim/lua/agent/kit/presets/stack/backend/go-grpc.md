<!-- name: Go gRPC / Connect -->
<!-- desc: Go RPC services: protobuf with buf, connect-go (gRPC + HTTP/JSON), protovalidate, pgx + sqlc -->

# STACK.md: Go gRPC / Connect

## Summary

Backend services that speak protobuf RPC. The `.proto` files are the contract, linted and checked for breaking changes
with buf; servers are implemented with connect-go, which serves gRPC, gRPC-Web and the Connect HTTP/JSON protocol from the
same handler. Hexagonal layout: RPC handlers and Postgres repositories are adapters around a domain that knows nothing
about protobuf.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Go 1.23+ | One static binary, first-class protobuf tooling |
| Contract | Protobuf (proto3 / editions) in `proto/`, managed with `buf` | Lint, format, breaking-change detection, code generation |
| RPC | `connectrpc.com/connect` | gRPC-compatible, plain `net/http`, works from browsers and curl |
| Validation | `buf.build/go/protovalidate` (rules in the `.proto`) | Constraints live in the contract, enforced by an interceptor |
| Database | PostgreSQL 16 | Relational, transactional |
| DB access | `jackc/pgx/v5` + `sqlc` | Hand-written SQL, generated type-safe Go |
| Migrations | `pressly/goose/v3` | Plain SQL, embedded |
| Config | env vars → typed struct (`caarlos0/env/v11`) | 12-factor |
| Logging | `log/slog` | Structured, standard library |
| Observability | `connectrpc.com/otelconnect` + OpenTelemetry | Traces and metrics per RPC |
| Health / reflection | `connectrpc.com/grpchealth`, `connectrpc.com/grpcreflect` | Load balancers and grpcurl/buf curl work |
| Testing | `testing` + `testify/require` + `testcontainers-go` | In-process servers with `httptest`, real Postgres |
| Lint | golangci-lint v2 + `buf lint` + `buf breaking` | Code and contract checked |
| Deploy | Distroless container, HTTP/2 (h2c behind a mesh or TLS) | Small, no shell |

## Project layout

```
buf.yaml                           modules, lint (STANDARD) and breaking (FILE) rules
buf.gen.yaml                       generation: protocolbuffers/go + connectrpc/go
proto/<org>/<context>/v1/          one package per bounded context and version
  order_service.proto              service + request/response messages
  order.proto                      shared messages of the context
gen/                               generated Go (never edited)
cmd/server/main.go                 composition root: config, pool, repositories, services, interceptors, mux, server
internal/
  domain/<context>/                entities, value objects, domain errors, ports — no protobuf imports
  app/<context>/                   use cases: one file per use case (place_order.go)
  adapters/
    rpc/<context>/handler.go       implements the generated Connect handler: proto → use case input → proto
    rpc/<context>/mapping.go       proto ↔ domain conversions, one direction per function
    rpc/errors.go                  domain error → connect.Code, in ONE place
    rpc/interceptors/              one interceptor per file (auth.go, validate.go, logging.go, recover.go)
    postgres/<context>_repo.go     implements the domain port with sqlc queries
    postgres/queries/*.sql         sqlc input
    postgres/db/                   sqlc output (generated)
migrations/                        goose migrations
```

Dependency direction: `adapters → app → domain`. Only `adapters/rpc` imports `gen/`; `domain` never sees a proto type.

## Conventions

- One file = one responsibility: one service handler, one mapping file, one use case, one interceptor.
- Proto packages are versioned (`acme.order.v1`); a breaking change means a new version package, never an edit in place.
- Follow buf's STANDARD lint: `XxxRequest`/`XxxResponse` per RPC, enum zero values `XXX_UNSPECIFIED`, fields `snake_case`.
- Field numbers are never reused; removed fields are `reserved` (number and name).
- Handlers are thin: map, call one use case, map back. Errors become `connect.NewError(code, err)` only in `rpc/errors.go`.
- `context.Context` carries deadlines and identity; every RPC honours cancellation.
- List RPCs paginate with `page_size` + `page_token` (AIP-158 style), with a server-side maximum.
- New RPC = `.proto` change → `buf lint && buf breaking` → `buf generate` → use case + test → repository → handler → register.

## Commands

| Task | Command |
| --- | --- |
| Generate | `buf generate && sqlc generate` |
| Contract lint | `buf lint && buf format -d --exit-code` |
| Breaking check | `buf breaking --against '.git#branch=main'` |
| Run | `go run ./cmd/server` |
| Call an RPC | `buf curl --schema proto --data '{"id":"1"}' http://localhost:8080/acme.order.v1.OrderService/GetOrder` |
| Build | `CGO_ENABLED=0 go build -o bin/server ./cmd/server` |
| Test | `go test -race ./...` |
| Integration tests | `go test -race -tags=integration ./...` |
| Lint | `golangci-lint run` |
| Migrate | `goose -dir migrations postgres "$DATABASE_URL" up` |

## Testing

- Domain and use cases: table-driven unit tests with in-memory fakes of the ports.
- Handlers: start the real Connect handler in `httptest.NewUnstartedServer` (HTTP/2 enabled) and call it with the generated client; assert response messages and `connect.CodeOf(err)`.
- Validation: tests for each protovalidate rule that matters (invalid request → `CodeInvalidArgument`).
- Repositories: integration tests with testcontainers Postgres, each test in a rolled-back transaction.
- Mapping: round-trip tests proto → domain → proto for every message with logic.

## Quality gates

- `buf lint`, `buf format --exit-code` and `buf breaking` against the main branch pass.
- `golangci-lint run` with zero issues; `go test -race ./...` passes.
- Generated code (`gen/`, `postgres/db/`) is committed and CI fails on a diff after regenerating.
- `govulncheck ./...` reports nothing.

## Dependencies

- Standard library and the Connect ecosystem first.
- Allowed: the table above; anything else needs a reason in the PR.
- Do NOT use: `protoc` invoked by hand or ad-hoc scripts — buf owns generation; gogo/protobuf (dead); `grpc-gateway` when Connect's JSON protocol is enough; ORMs; hand-written validation that duplicates protovalidate rules.

## Rules for agents

- Change the `.proto` first, run `buf lint` and `buf breaking`, then `buf generate`; never edit `gen/`.
- Never reuse or renumber a field; mark removed ones `reserved`.
- Never import generated proto types outside `adapters/rpc`; map to domain types at the boundary.
- Return errors with the right `connect.Code` from `rpc/errors.go`; never `CodeUnknown` for a known domain error, never leak SQL text.
- Put request constraints in protovalidate annotations, not in handler `if`s.
- Every RPC respects the context deadline and passes it to the database calls.
- Every query goes through sqlc; schema changes come with a goose migration.
- Every new RPC ships with a handler test through the generated client.
