# SQL (PostgreSQL, SQLite)

Filetype: `sql`. Pack `sql`.

## Tools

| What | With |
|---|---|
| Completion of tables and columns | `sqls`, connected to the project's database (below) |
| Format on save | `sql-formatter` in the project's dialect (PostgreSQL, or SQLite when the connection is SQLite) |
| Run | `psql` / `sqlite3` (they must be installed): no resident process |
| Treesitter | `sql` |

## Connections: found, never asked

In this order, without duplicates:
1. `settings.sql.connections` (`{ name = "local", url = "postgres://…" }` or `{ name = "data", sqlite = "data/app.db" }`).
2. The project's `.env`, `.env.local`, `.env.development`: `DATABASE_URL`, then any `*_DATABASE_URL`, `*_DB_URL`,
   `POSTGRES_URL`, `DB_URL`.
3. `DATABASE_URL` of the environment Neovim was started in.
4. The SQLite files under the root (`*.db`, `*.sqlite`, `*.sqlite3`; not in `node_modules`, `.git`, `target`, `.venv`).

The first is used; `<leader>Qc` picks another and it is remembered per project (state dir). Passwords are never shown
(`postgres://app:•••@localhost/app`). A `config.yml` at the root (sqls' own) still wins for completion.

## `<leader>Q` menu (only in `*.sql`)

The keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md). What they do:

- **Run the statement under the cursor** (in visual mode: the selection), or the whole file. A statement ends at a `;`
  outside strings, comments and dollar-quoted bodies (`$$ … $$`, as PostgreSQL functions are written). The result
  opens in one split (`sql://results`): the connection, how long it took, the rows as the client draws them (psql's
  table, sqlite3's boxes; `∅` for NULL); `r` there runs it again, `q` closes.
- **Asks before it hurts**: a DELETE or UPDATE with no WHERE, DROP TABLE/SCHEMA, TRUNCATE, ALTER TABLE … DROP
  (`settings.sql.confirm_risky`).
- **Explain**: the plan of the statement (`EXPLAIN`, SQLite's `EXPLAIN QUERY PLAN`); **explain analyze** runs it, so
  anything but a read asks first.
- **Schema**: the tables (`\dt+`, `.tables`), the table under the cursor described (`\d+`, `.schema`).

## Snippets

`createtable` (identity id, timestamps), `createindex`, `upsert` (`on conflict … do update`), `withquery`, `transaction`.

## Pitfalls

- psql reads `~/.pgpass` and `PG*` variables as usual: a URL without a password works when those have it.
- A long query stops after `settings.sql.timeout_ms` (30 s).
