<!-- name: SQLx -->
<!-- desc: async Rust SQL with compile-time checked queries and migrations embedded in the binary -->
<!-- for: rust -->

## Stack

| Data access | SQLx (async, `query!`/`query_as!` checked at compile time, `sqlx migrate`) | Plain SQL verified against the real schema by the compiler |

## Project layout

```
migrations/                    timestamped SQL migrations (`sqlx migrate add <name>`)
.sqlx/                         offline query metadata (`cargo sqlx prepare`), committed
src/db.rs                      pool creation and repository functions
```

## Conventions

- Create one `PgPool` (or `SqlitePool`) at startup and pass it through state; never open a connection per request.
- Prefer `query_as!` with a struct over untyped rows; map to domain types at the repository boundary.
- Embed migrations with `sqlx::migrate!()` and run them at startup or in the deploy step, not both.
- Multi-step writes use `pool.begin()` and an explicit `commit()`.
- CI builds with `SQLX_OFFLINE=true` so no database is needed to compile.

## Commands

| Migrate | `sqlx migrate run` |
| Migration new | `sqlx migrate add <name>` |
| Prepare | `cargo sqlx prepare` |

## Dependencies

- `sqlx` with the runtime (`tokio`), TLS and driver features you use; `sqlx-cli` installed with `cargo install sqlx-cli`.

## Rules for agents

- Never build a query with `format!`; use bind parameters (`$1`) or the macros.
- Commit `.sqlx/` after changing any query; CI fails when it is stale.
- Never edit an applied migration.
