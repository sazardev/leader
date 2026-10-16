<!-- name: Go + SQLite (tiny service) -->
<!-- desc: one static Go binary + SQLite (WAL), Litestream backups to S3, Caddy; < 50 MB RAM, nothing else to run -->

# STACK.md: Go + SQLite (tiny service)

## Summary

A small self-hosted service that one person can run for years on the cheapest server: one static Go binary, one SQLite
database file in WAL mode, Litestream continuously replicating that file to S3-compatible storage, and Caddy in front
for HTTPS. No database server, no queue, no cache: SQLite on local disk handles thousands of reads per second and
writes serialized through one connection. Target: under 50 MB RAM, a cold start under a second, restore from backup in
one command.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Go 1.25+ | Static binary, low memory, standard library HTTP |
| HTTP | `net/http` (Go 1.22+ pattern routing) | No framework needed |
| Database | SQLite 3 in WAL mode via `modernc.org/sqlite` (pure Go, `CGO_ENABLED=0`) | Embedded, zero ops; `mattn/go-sqlite3` if CGO is fine and speed matters |
| Queries | `sqlc` (sqlite engine) or hand-written `database/sql` | Explicit SQL, generated types |
| Migrations | embedded SQL files run at startup (`goose` with `embed`) | The binary migrates itself |
| Backups | Litestream → S3-compatible bucket (Backblaze B2, R2, MinIO) | Continuous, point-in-time restore |
| TLS / proxy | Caddy 2 | Automatic HTTPS, compression |
| Templates (if UI) | `html/template` or templ + htmx | Server-rendered, no build chain |
| Logging | `log/slog` JSON to stdout | Read with `docker logs`/journald |
| Testing | `testing` with a temp SQLite file per test | Real database, milliseconds |
| Lint | golangci-lint v2 | Zero issues |
| Deploy | Single container (`scratch`/distroless) or binary + systemd | Litestream as entrypoint wrapper |

## Project layout

```
cmd/server/main.go              config, open DB (pragmas), migrate, wire handlers, http.Server with timeouts, graceful shutdown
internal/
  config/config.go              env → struct, validated
  db/
    open.go                     DSN + pragmas: journal_mode=WAL, busy_timeout=5000, foreign_keys=ON, synchronous=NORMAL
    migrations/                 0001_init.sql … (embedded)
    queries/*.sql               sqlc input
    gen/                        sqlc output (generated)
  <feature>/                    one folder per feature
    service.go                  rules and use cases
    store.go                    port + SQLite implementation
    handler.go                  HTTP: parse → service → respond
  web/                          templates and static assets (embedded)
litestream.yml                  replica config (bucket from env)
Dockerfile                      build static binary → copy with litestream into the final image
```

Dependency direction: `cmd → feature handlers → services → stores → db`. Handlers never run SQL.

## Conventions

- Two pools: one write connection (`SetMaxOpenConns(1)`) and a read pool; writes are short transactions (`BEGIN IMMEDIATE`).
- Every request has a timeout (`http.Server` Read/Write/Idle timeouts + `context` deadlines on queries).
- Configuration only from env; the DB path points to a mounted volume (`/data/app.db`).
- The container entrypoint is `litestream replicate -exec /app/server`; on first start with no DB, `litestream restore -if-replica-exists` runs before it.
- `GET /healthz` checks the DB with a `SELECT 1`; logs are JSON lines.
- New feature = folder with service/store/handler + migration + queries + tests.

## Commands

| Task | Command |
| --- | --- |
| Run | `go run ./cmd/server` |
| Build | `CGO_ENABLED=0 go build -ldflags='-s -w' -o bin/server ./cmd/server` |
| Test | `go test ./...` |
| Generate | `sqlc generate` |
| Lint | `golangci-lint run` |
| Format | `gofmt -w .` |
| Restore backup | `litestream restore -o /data/app.db s3://bucket/app.db` |
| Container | `docker build -t app . && docker run -v app-data:/data -p 8080:8080 app` |

## Testing

- Every test opens its own SQLite file in `t.TempDir()` with the production pragmas and runs migrations.
- Services: unit tests on real SQLite (fast enough that fakes are rarely needed).
- Handlers: `httptest` end to end through service and DB.
- A restore drill script (restore to a temp path, open, count rows) runs in CI weekly.

## Quality gates

- `gofmt` clean, golangci-lint zero issues, `go test -race ./...` green.
- The final image is under 30 MB and the server idles under 50 MB RSS (checked in CI with a smoke run).

## Dependencies

- Standard library, the SQLite driver, sqlc/goose, Litestream (as a binary). Anything else needs a reason.
- Do NOT use: Postgres/Redis for this size, an ORM, an in-process cache in front of SQLite before measuring, network filesystems (NFS/SMB) for the DB file, several writer processes on one database.

## Rules for agents

- Never open the database without the WAL, busy_timeout and foreign_keys pragmas from `db/open.go`.
- All writes go through the single write connection; keep write transactions short and never do network IO inside one.
- Never store the database inside the image or on a network share; it lives on a local volume.
- Every schema change is a new embedded migration; never edit an applied one.
- Never build SQL with string concatenation; use sqlc queries or `?` parameters.
- Keep the binary static (`CGO_ENABLED=0` unless the driver choice says otherwise) and the image minimal.
- Any change to storage paths or Litestream config comes with an updated restore procedure.
- Measure before optimizing: add an index or a cache only with a query plan (`EXPLAIN QUERY PLAN`) or a benchmark.
