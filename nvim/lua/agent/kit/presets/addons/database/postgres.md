<!-- name: PostgreSQL -->
<!-- desc: the default relational database: versioned SQL migrations, a pooled connection, real database in tests -->
<!-- for: server backend fullstack selfhosted !mobile -->

## Stack

| Database | PostgreSQL 17 (`DATABASE_URL`, versioned migrations, connection pool) | Transactions, constraints and types that keep data correct as the app grows |

## Project layout

```
migrations/                    numbered, forward-only SQL migrations (one change each)
compose.yaml                   local `postgres` service with a named volume and a healthcheck
```

## Conventions

- Connection string only from `DATABASE_URL`; one pool per process, sized explicitly.
- Schema lives in migrations, never in manual `psql` sessions; a migration never edits an applied one.
- Primary keys on every table, foreign keys and `NOT NULL` where the domain says so; money as `numeric` or integer cents, time as `timestamptz` in UTC.
- Index every foreign key and every column used in a frequent `WHERE`/`ORDER BY`; check slow queries with `EXPLAIN ANALYZE`.
- Statements always use bound parameters; the migration tool comes from the Data access row.

## Commands

| Database up | `docker compose up -d postgres` |
| Shell | `psql "$DATABASE_URL"` |

## Testing

- Integration tests run against a real PostgreSQL (container or a throwaway schema per test run), never an in-memory fake.
- Each test starts from a known state (transaction rollback or truncate), so tests do not depend on order.

## Rules for agents

- Never build SQL by concatenating user input.
- Never edit a migration that has been applied; add a new one.
- A destructive migration (drop, type change) needs a backward-compatible step first and an explicit mention in the commit.
- Never run migrations or destructive statements against a production `DATABASE_URL`.
