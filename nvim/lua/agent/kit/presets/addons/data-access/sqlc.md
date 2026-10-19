<!-- name: sqlc -->
<!-- desc: write SQL, get type-safe Go code: queries in .sql files compiled by sqlc, migrations with goose -->
<!-- for: go -->

## Stack

| Data access | sqlc (SQL queries in `.sql` files compiled to typed Go, `pgx` driver, migrations with `goose`) | Plain SQL reviewed as SQL, generated code with no runtime reflection |

## Project layout

```
sqlc.yaml                      engine, schema (migrations folder), queries folder, output package
db/migrations/                 goose SQL migrations (the schema sqlc reads)
db/queries/                    one .sql file per aggregate, each query named with `-- name: GetUser :one`
internal/db/                   generated code (never edited by hand), committed
```

## Conventions

- Write the query in `db/queries/`, run `sqlc generate`, commit the generated code.
- Name queries by intent (`ListOrdersByCustomer`) and annotate with `:one`, `:many`, `:exec`.
- Repositories wrap the generated `Queries`; handlers never import `internal/db` directly.
- Transactions use `pool.Begin` and `queries.WithTx(tx)`.
- Use `sqlc.arg` / `sqlc.narg` for named and nullable parameters.

## Commands

| Generate | `sqlc generate` |
| Vet | `sqlc vet` |
| Migrate | `goose -dir db/migrations postgres "$DATABASE_URL" up` |
| Migration new | `goose -dir db/migrations create <name> sql` |

## Rules for agents

- Never edit files in `internal/db/`; change the `.sql` and regenerate.
- CI fails if `sqlc generate` leaves a diff.
- Never build SQL strings by concatenation outside sqlc; use parameters.
