<!-- name: Rust Axum -->
<!-- desc: Rust API: Axum + tokio + tower, sqlx (Postgres, checked queries), tracing, thiserror/anyhow, nextest -->

# STACK.md: Rust Axum

## Summary

An async HTTP API in Rust on tokio. Axum routes requests through tower middleware; sqlx checks SQL against the database
at compile time; tracing gives structured logs and spans. Hexagonal layout in a Cargo workspace: the domain crate has no
IO dependencies, adapters live in their own crates, and the binary wires them together.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Rust stable (edition 2021/2024), `rust-toolchain.toml` pinned | Reproducible toolchain |
| Async runtime | `tokio` | De facto standard |
| HTTP | `axum` + `tower` + `tower-http` (trace, cors, timeout, compression, request-id) | Composable middleware, typed extractors |
| Serialization | `serde` + `serde_json` | Standard |
| Validation | `validator` (derive) or newtype constructors returning `Result` | Invalid states unrepresentable |
| Database | PostgreSQL 16 | Relational, transactional |
| DB access | `sqlx` (postgres, runtime-tokio, macros) | `query!`/`query_as!` checked at compile time; offline mode for CI |
| Migrations | `sqlx migrate` (`migrations/`) | SQL files, embedded with `sqlx::migrate!()` |
| Errors | `thiserror` in libraries/domain, `anyhow` only in `main` and scripts | Typed errors where they are handled |
| Config | `figment` or `config` + `serde` | Env → typed struct |
| Observability | `tracing` + `tracing-subscriber` (JSON) + `tracing-opentelemetry` | Spans per request |
| API docs | `utoipa` + `utoipa-axum` | OpenAPI from code |
| Testing | `cargo nextest` + `tokio::test` + `testcontainers` + `axum-test` or `tower::ServiceExt::oneshot` | Fast, isolated |
| Lint / format | `cargo clippy -- -D warnings`, `rustfmt` | Zero warnings |

## Project layout

```
Cargo.toml                         workspace: members, shared [workspace.dependencies] and [workspace.lints]
rust-toolchain.toml
crates/
  domain/                          entities, value objects, domain errors, ports (traits) — no tokio/sqlx/axum
    src/order/mod.rs
    src/order/entity.rs            Order + invariants
    src/order/status.rs            value object
    src/order/repository.rs        trait OrderRepository (async fn in trait)
    src/order/error.rs             OrderError (thiserror)
  application/                     use cases: one module per use case (place_order.rs), generic over ports
  infra-postgres/                  sqlx implementations of the ports
    src/order_repository.rs
  api/                             axum routers, extractors, DTOs, error → response mapping
    src/order/routes.rs
    src/order/dto.rs
    src/error.rs                   ApiError: IntoResponse; domain errors → status in ONE place
    src/state.rs                   AppState (Arc'd services)
  server/                          the binary: config, pool, wiring, tracing, graceful shutdown
    src/main.rs
migrations/                        sqlx migrations (timestamped .sql)
.sqlx/                             offline query metadata (committed)
```

Dependency direction: `server → api → application → domain`, `server → infra-postgres → domain`. `domain` depends only on `thiserror` and std (plus `serde` if needed).

## Conventions

- One module = one responsibility; modules over ~300 lines are split.
- Newtypes for identifiers and validated values (`OrderId(Uuid)`, `Email(String)` with a fallible constructor).
- Handlers are thin: extractors → one use case → DTO → response. No SQL in `api`.
- Errors: each layer has its own `thiserror` enum; conversions via `From`; `ApiError` maps to status codes; never expose internal messages.
- No `unwrap()`/`expect()` outside tests and startup; `?` everywhere else.
- Shared state is `AppState` with `Arc<dyn Trait + Send + Sync>` or generics; no global statics except `tracing`.
- Every handler is `#[tracing::instrument(skip(state))]` with the relevant ids as fields.
- New feature = domain types + trait → use case + test → sqlx implementation + migration → routes + DTOs → mount in the router.

## Commands

| Task | Command |
| --- | --- |
| Run | `cargo run -p server` (watch: `cargo watch -x 'run -p server'` or `bacon`) |
| Build | `cargo build --release -p server` |
| Test | `cargo nextest run --workspace` |
| Doc tests | `cargo test --doc --workspace` |
| Lint | `cargo clippy --workspace --all-targets -- -D warnings` |
| Format | `cargo fmt --all` |
| Migrate | `sqlx migrate run` |
| New migration | `sqlx migrate add -r <change>` |
| Offline query data | `cargo sqlx prepare --workspace` |
| Audit | `cargo deny check` |

## Testing

- Domain and application: unit tests in the same file (`#[cfg(test)] mod tests`) with in-memory fake ports.
- API: build the router with fake state and call it with `tower::ServiceExt::oneshot`; assert status and JSON.
- Postgres adapter: integration tests in `crates/infra-postgres/tests/` with `#[sqlx::test]` (fresh database per test, migrations applied) or testcontainers.
- Property tests (`proptest`) for value objects with parsing/validation rules.
- A bug fix starts with a failing test.

## Quality gates

- `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings` (with `clippy::pedantic` selectively enabled in `[workspace.lints]`).
- `cargo nextest run` passes; `SQLX_OFFLINE=true cargo build` works (`.sqlx/` up to date).
- `cargo deny check` (licenses, advisories, duplicate versions) passes.
- `#![forbid(unsafe_code)]` in every crate unless a reviewed exception.

## Dependencies

- Versions declared once in `[workspace.dependencies]`; crates inherit them.
- Allowed: the table above; anything else needs a reason in the PR (maintenance, downloads, `cargo deny` result).
- Do NOT use: Diesel alongside sqlx; `actix-web` (one framework); `anyhow` in library crates; `lazy_static` (use `std::sync::LazyLock`); `async-trait` when native async fn in traits works; `openssl` when `rustls` works.

## Rules for agents

- Never `unwrap()`/`expect()`/`panic!` in non-test code paths that handle requests.
- Never add a dependency to `domain`; it stays free of IO crates.
- Write SQL with `sqlx::query!`/`query_as!` macros (checked); run `cargo sqlx prepare` after changing a query and commit `.sqlx/`.
- Never build SQL by formatting strings with user input.
- Map errors only in `api/src/error.rs`; never return internal error text to clients.
- Every schema change is a reversible sqlx migration; never edit an applied one.
- Hold no lock (`Mutex` guard) across an `.await`; use `tokio::sync` primitives when needed.
- Run `cargo fmt`, `cargo clippy -D warnings` and `cargo nextest run` before declaring a change done.
