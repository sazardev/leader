<!-- name: Turso (libSQL) -->
<!-- desc: SQLite-compatible hosted database (libSQL) with embedded replicas, per-environment databases and migrations -->
<!-- for: ts js node bun rust go !mobile -->

## Stack

| Database | Turso (libSQL, `TURSO_DATABASE_URL` + `TURSO_AUTH_TOKEN`, local `file:` URL in dev) | SQLite semantics with a hosted, replicated service and edge reads |

## Project layout

```
migrations/                    numbered, forward-only SQL migrations (SQLite dialect)
```

## Conventions

- URL and token only from environment variables; development and tests use a local `file:` database, never the production one.
- One database per environment (dev, staging, prod); create with the Turso CLI (`turso db create`).
- SQLite rules apply: `foreign_keys` on, `STRICT` tables where available, no server-only SQL.
- Batch related statements in one transaction or `batch` call to save round trips.
- The auth token is scoped to one database; rotate it with `turso db tokens create`.

## Commands

| Database up | `turso dev --db-file data/dev.db` |
| Shell | `turso db shell <database>` |

## Testing

- Tests run against a local libSQL file with the real migrations applied, one file per test run.

## Rules for agents

- Never commit `TURSO_AUTH_TOKEN` or a `.db` file.
- Never point tests or local development at a remote database.
- Always bind parameters; never concatenate user input into SQL.
