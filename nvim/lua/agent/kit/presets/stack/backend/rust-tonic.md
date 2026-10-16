<!-- name: Rust + tonic (gRPC) -->
<!-- desc: gRPC services in Rust: tonic + prost + tokio + tower, buf-managed protos, sqlx with Postgres -->

# STACK.md: Rust + tonic (gRPC)

## Summary

Backend services that speak gRPC, written in Rust. The `.proto` files are the contract: linted and checked for breaking
changes with buf, compiled to Rust with `tonic-build` (prost). tonic serves them on tokio, with tower middleware for
timeouts, tracing and auth. Hexagonal layout in a Cargo workspace: the domain crate knows nothing about protobuf or SQL;
gRPC handlers and sqlx repositories are adapters.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Rust stable, edition 2024 | Performance, memory safety, strong types end to end |
| Contract | Protobuf in `proto/`, managed with `buf` (lint, format, breaking) | The API is reviewed as a contract |
| RPC | `tonic` + `prost` (codegen with `tonic-build` in `build.rs`) | Mature gRPC stack on tokio and hyper |
| Runtime | `tokio` | De-facto async runtime |
| Middleware | `tower` + `tower-http` (timeout, trace, limits) | Composable layers |
| Health / reflection | `tonic-health`, `tonic-reflection` | Load balancers and grpcurl work |
| Database | PostgreSQL 16 + `sqlx` (compile-time checked queries, migrations) | SQL by hand, checked against the schema |
| Errors | `thiserror` in domain/adapters, mapped to `tonic::Status` in one place | Typed errors, consistent status codes |
| Config | env vars → struct (`figment` or `envy` + `serde`) | 12-factor, validated at startup |
| Observability | `tracing` + `tracing-subscriber` (JSON) + `tracing-opentelemetry` | Spans per RPC |
| Testing | `cargo nextest`, in-process server on a random port, `testcontainers` for Postgres | Real network and DB |
| Lint | `cargo clippy -- -D warnings`, `cargo fmt`, `cargo deny` | Zero warnings, license/advisory checks |
| Deploy | Container from `debian:bookworm-slim` or distroless `cc` | Small image, glibc for TLS/DB drivers |

## Project layout

```
proto/acme/orders/v1/orders.proto   contract (package acme.orders.v1)
buf.yaml / buf.gen.yaml             lint/breaking rules
Cargo.toml                          workspace
crates/
  domain/                           entities, value objects, errors, ports (traits); no tonic, no sqlx
    src/order.rs
    src/order_repository.rs         `#[async_trait]`/native async trait port
    src/errors.rs
  app/                              use cases, one file each (place_order.rs, cancel_order.rs)
  api/                              tonic adapter
    build.rs                        tonic_build::configure().compile_protos(...)
    src/orders_service.rs           impl OrdersService: request → use case → response
    src/convert.rs                  proto ↔ domain conversions
    src/status.rs                   domain error → tonic::Status (the only place)
  storage/                          sqlx adapter
    src/pg_order_repository.rs
    migrations/                     sqlx migrations (0001_orders.sql)
  server/src/main.rs                config, pool, repositories, use cases, tower layers, Server::builder(), graceful shutdown
```

Dependency direction: `server → api, storage → app → domain`. `domain` has no dependency on tonic, prost or sqlx;
generated proto types never leave `api`.

## Conventions

- Proto packages are versioned (`acme.orders.v1`); a breaking change is a new version, never an edit (`buf breaking` in CI).
- One use case per file; handlers only convert, call one use case, and map errors.
- Domain errors map to status codes in `status.rs` only (NotFound → `NOT_FOUND`, validation → `INVALID_ARGUMENT`…).
- Every RPC has a deadline: a tower timeout layer plus client deadlines; cancellation is respected via tokio.
- Queries use `sqlx::query!`/`query_as!` (checked); `cargo sqlx prepare` output is committed for offline builds.
- No `unwrap()`/`expect()` outside tests and startup.
- New RPC = proto change → codegen → use case → handler + conversion → test.

## Commands

| Task | Command |
| --- | --- |
| Build | `cargo build --workspace` |
| Run | `cargo run -p server` |
| Test | `cargo nextest run --workspace` |
| Lint | `cargo clippy --workspace --all-targets -- -D warnings && buf lint` |
| Format | `cargo fmt && buf format -w` |
| Breaking check | `buf breaking --against '.git#branch=main'` |
| Migrate | `sqlx migrate run --source crates/storage/migrations` |
| Prepare queries | `cargo sqlx prepare --workspace` |
| Call an RPC | `grpcurl -plaintext localhost:50051 list` |

## Testing

- Domain and use cases: unit tests with in-memory fakes of the ports.
- Repositories: integration tests against Postgres in testcontainers, migrations applied per test DB.
- RPCs: start the server in-process on `127.0.0.1:0`, call it with the generated client, assert on responses and status codes.
- Conversions proto ↔ domain: round-trip tests.

## Quality gates

- `cargo fmt --check`, `cargo clippy -D warnings`, `buf lint`, `buf breaking` and `cargo deny check` clean.
- `cargo nextest run` green; `cargo sqlx prepare --check` passes (offline query data current).

## Dependencies

- tonic/prost/tokio/tower/sqlx/tracing/thiserror as above; anything else needs a reason.
- Do NOT use: hand-written protobuf types, `anyhow` in library crates (use it only in `server`), an ORM (Diesel/SeaORM) next to sqlx, blocking calls inside async handlers (use `spawn_blocking`).

## Rules for agents

- Never edit generated code; change the `.proto` and rebuild.
- Never change a field number or type in a released proto package; add fields or create `v2`.
- Map errors to `tonic::Status` only in `api/src/status.rs`; never leak internal error text to clients.
- Generated proto types stay in `api`; convert to domain types at the boundary.
- Every query goes through sqlx macros; never build SQL with `format!`.
- Every new RPC has an in-process integration test, including an error path.
- No `unwrap()` in non-test code; propagate with `?` and typed errors.
- Keep `server/main.rs` the only place where concrete types are wired together.
