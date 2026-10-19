<!-- name: Go entity with its repository -->
<!-- desc: a domain entity, its repository port, an in-memory adapter and the SQL adapter when STACK.md names a database -->
<!-- for: go -->
<!-- input: name | Name of the entity (e.g. Order, Customer) -->
<!-- input: fields | Its fields and rules (e.g. total > 0, status draft|paid|cancelled) -->

# Recipe: the {{name_pascal}} entity

Fields and rules: {{fields}}.

## Make

- `{{name_pascal}}` in the domain package: unexported fields where it has invariants, a `New{{name_pascal}}(…) ({{name_pascal}}, error)` constructor that enforces them, methods for its state changes, and sentinel errors (`Err{{name_pascal}}NotFound`, one per broken rule).
- The port `{{name_pascal}}Repository` (interface) next to the domain or in the application layer, as the project does: only the methods the use cases need, `context.Context` first, domain types in and out.
- An in-memory adapter (`{{name_camel}}Memory` or the project's naming), safe for concurrent use, used by tests.
- When STACK.md names a database: the SQL adapter with the project's driver/query tool (pgx, database/sql, sqlc, GORM) and the migration that creates its table, in the folder the existing migrations use.

## Rules

- The domain imports nothing from adapters; adapters translate their errors to the domain's (`sql.ErrNoRows` → `Err{{name_pascal}}NotFound`).
- A `var _ {{name_pascal}}Repository = (*…)(nil)` line per adapter so the compiler checks it.

## Tests

- Table tests for the constructor and each state change: valid input, each rule broken.
- One contract test suite run against every adapter (save, get, update, not found).
