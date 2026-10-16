<!-- name: Go workspace -->
<!-- desc: Go multi-module monorepo: go.work, services + shared libs, buf for protobuf, per-module CI -->

# STACK.md: Go workspace

## Summary

A Go monorepo with several modules tied together by a `go.work` file: each service is its own module with its own
`go.mod`, shared code lives in library modules, and API contracts are Protobuf files compiled with buf. Services are
hexagonal inside (domain, application, adapters) and talk to each other only through the published contracts
(gRPC/Connect or events), never by importing each other's internals. CI runs per module, triggered by path filters.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Go 1.23+ | One static binary per service |
| Workspace | `go.work` (local development), each module versioned on its own | Independent modules, one checkout |
| Contracts | Protobuf + `buf` (lint, breaking checks, generate) | Typed, versioned APIs |
| RPC | `connectrpc.com/connect` (gRPC compatible) or `google.golang.org/grpc` | HTTP/1.1 + HTTP/2, browser friendly |
| HTTP | `net/http` (Go 1.22 patterns) or `chi` | Standard |
| Database | PostgreSQL + `pgx/v5` + `sqlc` per service | Each service owns its data |
| Messaging | NATS JetStream or Kafka (via `franz-go`) | Async integration between services |
| Config | env → struct | 12-factor |
| Logging/tracing | `log/slog` + OpenTelemetry | Correlated logs and traces |
| Testing | `testing`, testcontainers-go | Real dependencies in integration tests |
| Lint | golangci-lint v2 per module | Same config everywhere |
| Build | `ko` or multi-stage Docker, one image per service | Small images |
| CI | GitHub Actions with `paths` filters / matrix per module | Only changed modules build |

## Project layout

```
go.work                          use ./services/orders ./services/billing ./libs/platform ./gen/go
proto/
  buf.yaml, buf.gen.yaml
  acme/orders/v1/orders.proto    versioned packages (v1, v2…)
gen/go/                          generated code module (never edited)
libs/
  platform/                      module: logging, config, otel setup, http/grpc server helpers
    go.mod
services/
  orders/
    go.mod                       module example.com/acme/services/orders
    cmd/orders/main.go           wiring only
    internal/domain/             entities, ports
    internal/app/                use cases (one per file)
    internal/adapters/postgres/  repositories (sqlc)
    internal/adapters/rpc/       Connect/gRPC handlers implementing the proto service
    migrations/
  billing/ ...
.github/workflows/orders.yml     paths: services/orders/**, libs/**, gen/go/**
```

Dependency direction: `services → libs, gen`; `libs → stdlib/third-party only`. A service never imports another service's module; it uses the generated client from `gen/go`. Inside a service: `adapters → app → domain`.

## Conventions

- Each module has its own `go.mod`; `go.work` is for local development and is committed with every module listed.
- Shared libraries are small and stable; business logic is never shared through `libs/` (each service owns its domain).
- Proto packages are versioned (`acme.orders.v1`); breaking changes need a new version, enforced by `buf breaking`.
- One file = one responsibility (entity, use case, handler, repository); `internal/` for everything not meant for other modules.
- Each service owns its database schema and migrations; no service reads another's tables.
- Errors wrapped with context; mapped to RPC status codes in the adapter only.
- New service = `services/<name>` module from the template + `go work use` + CI workflow + proto package.

## Commands

| Task | Command |
| --- | --- |
| Sync workspace | `go work sync` |
| Add module | `go work use ./services/<name>` |
| Generate protos | `buf generate` |
| Lint protos | `buf lint && buf breaking --against '.git#branch=main'` |
| Build all | `go build ./services/... ./libs/...` (from each module, or `make build`) |
| Test a module | `cd services/orders && go test ./...` |
| Test all | `go list -m -f '{{.Dir}}' \| xargs -I{} sh -c 'cd {} && go test ./...'` |
| Lint | `golangci-lint run ./...` (per module) |
| Tidy | `go mod tidy` in every module |
| Run | `go run ./services/orders/cmd/orders` |

## Testing

- Domain and use cases: unit tests with in-memory fakes of ports.
- Adapters: integration tests with testcontainers (Postgres, NATS) behind a build tag.
- RPC handlers: in-process Connect server + generated client; assert codes and messages.
- Contract safety: `buf breaking` on every PR touching `proto/`.
- Tests run per module in CI, plus all dependents when `libs/` or `gen/` change.

## Quality gates

- `go vet`, golangci-lint and `go test -race` pass in every affected module.
- `buf lint` and `buf breaking` pass; generated code is committed and up to date.
- `go mod tidy` and `go work sync` leave no diff.
- No `replace` directives pointing outside the repo.

## Dependencies

- Standard library first; shared third-party versions kept aligned across modules (one upgrade PR).
- Do NOT use: one giant module for everything, importing another service's `internal` (impossible) or its module, shared database tables between services, hand-written gRPC stubs, `replace` directives as a substitute for `go.work`.

## Rules for agents

- Change a contract in `proto/` first, run `buf generate`, then update servers and clients.
- Never edit files under `gen/`.
- Never import one service from another; use the generated client or an event.
- Keep shared libs free of domain logic.
- Run `go mod tidy` in each module you touched and `go work sync` after dependency changes.
- New dependencies go in the module that uses them, not in every module.
- Every new RPC has a handler test and is backwards compatible within its version.
- Each `cmd/<service>/main.go` is the only wiring point of its service.
