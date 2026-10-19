<!-- name: SQLite -->
<!-- desc: a single-file database with WAL and foreign keys on: no server to run, easy backups -->
<!-- for: server backend fullstack selfhosted mobile cli-desktop !game -->

## Stack

| Database | SQLite (one file, WAL mode, `foreign_keys=ON`, versioned migrations) | Zero operations: no server, trivial backups, fast for one writer |

## Project layout

```
migrations/                    numbered, forward-only SQL migrations
data/app.db                    the database file (git-ignored; with its -wal and -shm files)
```

## Conventions

- Path from configuration (`DATABASE_PATH`); the directory is a persistent volume in containers.
- On every connection: `PRAGMA journal_mode=WAL`, `PRAGMA foreign_keys=ON`, `PRAGMA busy_timeout=5000`.
- One writer at a time: keep write transactions short and never hold one across a network call.
- Types are loose: add `CHECK` constraints and `STRICT` tables where the driver supports them.
- Back up with `sqlite3 data/app.db ".backup out.db"`, never by copying a live file.

## Commands

| Shell | `sqlite3 data/app.db` |
| Backup | `sqlite3 data/app.db ".backup backup.db"` |

## Testing

- Tests use a temporary file or `:memory:` with the real migrations applied, so schema and constraints are the production ones.

## Rules for agents

- Never commit the `.db`, `-wal` or `-shm` files; add them to `.gitignore`.
- Never open the same database from several processes that write heavily; if that is needed, say so and propose PostgreSQL.
- Always bind parameters; never concatenate user input into SQL.
