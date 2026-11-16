# SQL (PostgreSQL, SQLite, MySQL/MariaDB, SQL Server, DuckDB)

Filetype: `sql`. Pack `sql`.

## One connection, one dialect

Everything follows the connection: the client that runs a statement, the dialect SQLFluff lints, the language
sql-formatter pipes through, and the driver sqls uses for completion. The dialect is read from the URL scheme (or the
file extension), never guessed from the buffer:

| Engine | Connection | Client | sqls | SQLFluff | sql-formatter |
|---|---|---|---|---|---|
| PostgreSQL | `postgres://…` / `postgresql://…` | `psql` | `postgresql` | `postgres` | `postgresql` |
| SQLite | `sqlite:///path/app.db`, `file:…`, `app.db` | `sqlite3` | `sqlite3` | `sqlite` | `sqlite` |
| MySQL | `mysql://…` | `mysql` (or `mariadb`) | `mysql` | `mysql` | `mysql` |
| MariaDB | `mariadb://…` | `mariadb` (or `mysql`) | `mysql` | `mariadb` | `mariadb` |
| SQL Server | `sqlserver://…` / `mssql://…` | `sqlcmd` | `mssql` | `tsql` | `transactsql` |
| DuckDB | `duckdb:///path/app.duckdb`, `app.duckdb` | `duckdb` | — | `duckdb` | `duckdb` |

The connections of a project are found, never asked, in this order:

1. The ones added with `<leader>Qn` (kept per project in the state dir, never in `.env` or `settings`).
2. `settings.sql.connections` (`{ name = "local", url = "postgres://…" }`, `{ name = "data", sqlite = "data/app.db" }`,
   or `{ name = "ms", driver = "sqlserver", url = "Server=…;Database=…" }` when the string is a DSN instead of a URL).
3. The project's `.env`, `.env.local`, `.env.development`: `DATABASE_URL`, any `*_DATABASE_URL` / `*_DB_URL` /
   `*_DATABASE_URI`, `POSTGRES_URL`, `MYSQL_URL`, `MARIADB_URL`, `MSSQL_URL`, `SQLSERVER_URL`, `SQLITE_URL`.
4. `DATABASE_URL` of the environment Neovim was started in.
5. The SQLite and DuckDB files under the root (`*.db`, `*.sqlite`, `*.sqlite3`, `*.duckdb`, `*.ddb`; not in
   `node_modules`, `.git`, `target`, `.venv`, `build`, `dist`).

`<leader>Qc` picks one (remembered per project) and also offers **New connection…** (`<leader>Qn`): paste a URL or a
file path, and the dialect is detected from it. `Ctrl+x` in the picker removes a connection that was added there; the
ones in `.env` and `settings` are only read. Passwords are never shown (`postgres://app:•••@localhost/app`).

Adding a connection restarts `sqls` for the buffer, so completion follows the new default immediately. A `config.yml`
at the root (sqls' own) still wins over all of this.

## Tools

- **Completion and navigation** — `sqls`, connected to the real database: tables, columns, joins through foreign keys,
  hover and signature help. It starts with the project (`.env`, `.git`, `.sqlfluff`, `compose.yaml`… are its root
  markers). A project connection added with `<leader>Qn` becomes its default.
- **Linter and analyzer** — `sqlfluff` (`:MasonInstall sqlfluff`) runs on save and on leaving insert; parse and
  templating errors (`PRS`, `TMP`, `LXR`) are errors, the style rules are warnings. It always uses the connection's
  dialect, even when a `.sqlfluff` exists: the database is the source of truth. `<leader>QF` applies its fixes to the
  buffer (the same dialect, the project as cwd, so `.sqlfluff` still contributes its rules).
- **Format** — `sql-formatter` on save and `<leader>Qf`, in the connection's language. If the project has a
  `.sql-formatter.json`, its options are kept; the language is the one the database speaks.
- **Run** — the statement under the cursor (in visual mode: the selection) or the whole file, with the client above.
  No resident process: one process per run. `<leader>Qx` stops a query that is taking too long.
- **Schema** — `<leader>Qs` lists the tables (schema, kind, column count), Enter describes the columns in the results
  split, `Ctrl+y` puts the table name at the cursor. `<leader>Qt` and `<leader>Qd` are the quick `\dt+`/`\d+` forms.
- **History** — `<leader>Qh` lists what ran in this project, newest first (Enter inserts it, `Ctrl+r` runs it again);
  `settings.sql.history` caps it (100 by default, `0` turns it off).
- **Info** — `<leader>Qi` (or `:Sql info`) says the connection, the dialect, the four tools and what is missing, with
  the keys. `:checkhealth sqlrun` has the same facts without opening a panel.
- **Statusline** — a `PG app` / `SQLite data` / `MSSQL app` chip while a `*.sql` buffer is open; it turns yellow while
  a query runs and red for a minute after one failed.

The results split (`sql://results`) is text: `r` runs the last statement again (for a table described from the schema
browser, it describes it again), `q` closes it, `Ctrl+y` copies all of it (rows as the client draws them, `∅` for
NULL). The info panel is `sql://info` and uses the same keys.

## Menu and commands

The keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md). What they do:

- Run the statement under the cursor or the selection, run the file, explain, explain analyze (`EXPLAIN (ANALYZE,
  BUFFERS)` in PostgreSQL, `EXPLAIN QUERY PLAN` in SQLite, `EXPLAIN ANALYZE`/`ANALYZE FORMAT=JSON` in MySQL/MariaDB,
  `SET SHOWPLAN_ALL`/`SET STATISTICS PROFILE` in SQL Server, `EXPLAIN`/`EXPLAIN ANALYZE` in DuckDB).
- **Asks before it hurts**: DELETE/UPDATE with no WHERE, DROP TABLE/SCHEMA, TRUNCATE, ALTER TABLE … DROP
  (`settings.sql.confirm_risky`). Explain analyze only runs a read without asking.
- Tables, describe the table under the cursor, schema browser, connection picker, new connection, info, history, ping,
  stop, last run, format, SQLFluff fix.
- `:Sql` takes the same names: `:Sql run`, `:Sql explain`, `:Sql analyze`, `:Sql tables`, `:Sql describe`,
  `:Sql schema`, `:Sql connections`, `:Sql info`, `:Sql history`, `:Sql ping`, `:Sql fix`, `:Sql format`,
  `:Sql stop`, `:Sql new`. A bare `:Sql` opens the info panel.

## Setup

`<leader>QS` creates what is missing (never overwrites): `.sql-formatter.json` in the project's dialect (the language
comes from `DATABASE_URL`/`MYSQL_URL`/`MSSQL_URL`), a `compose.yaml` for PostgreSQL, MySQL, MariaDB or SQL Server,
`.editorconfig`, GitHub Actions. Presets live in `lua/langsetup/presets/sql/` and are filled from the URL and the
folder's name.

## Snippets

`createtable` (identity id, timestamps), `createindex`, `upsert` (`on conflict … do update`), `withquery`, `transaction`,
plus engine-specific ones: `mysqlcreatetable`, `mysqlupsert` (`on duplicate key update`), `sqliteupsert`,
`tsqlcreatetable` (identity + `datetime2`), `tsqlmerge` (`MERGE`).

## Pitfalls

- **PostgreSQL**: psql reads `~/.pgpass` and the `PG*` variables. A URL without a password fails (`-w`) instead of
  hanging the editor; add the password to the URL or to `.pgpass`.
- **MySQL/MariaDB**: the client takes `--host`, `--port`… from the URL; the password travels in `MYSQL_PWD`, never in
  argv. A local server without TLS needs `?ssl-mode=DISABLED` (MySQL) or the client's `--skip-ssl` (MariaDB).
- **SQL Server**: sqlcmd trusts the certificate of a localhost server (`-C`); for a remote one add
  `?trustServerCertificate=true`, or it will refuse the certificate. `GO` separates batches (functions and
  `SET SHOWPLAN_ALL` need it); a plain `;` is not enough for those.
- **SQLite/DuckDB**: the file is opened in place, so a migration or another client can lock it for a moment
  (sqlite3 gets a 5 s timeout). Relative paths are resolved against the project or the file's folder.
- **DuckDB**: sqls has no driver for it, so completion of the real tables is not available; the linter, formatter,
  runner and schema browser do work.
- A long query stops after `settings.sql.timeout_ms` (30 s); `<leader>Qx` stops one sooner. The schema queries use a
  shorter timeout (15 s).
