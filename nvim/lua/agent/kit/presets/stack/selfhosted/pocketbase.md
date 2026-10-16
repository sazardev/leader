<!-- name: PocketBase (Go framework) -->
<!-- desc: PocketBase extended in Go: SQLite, auth, realtime, admin UI, hooks and Go migrations in one binary -->

# STACK.md: PocketBase (Go framework)

## Summary

A self-hosted backend built on PocketBase used as a Go framework: one binary with an embedded SQLite database, auth
(email/password, OAuth2), file storage, realtime subscriptions, a REST API and an admin dashboard. The project imports
PocketBase as a Go module and adds its own routes, event hooks and Go migrations. Choose it for small-to-medium apps,
internal tools and prototypes that need a backend fast and must stay cheap to run; do not choose it for multi-region
writes, heavy write throughput, or a team that needs a separate database server.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Go 1.25+ | PocketBase is a Go library; custom logic in the same binary |
| Backend framework | `github.com/pocketbase/pocketbase` (pinned version) | Auth, collections, REST, realtime, admin UI included |
| Database | Embedded SQLite (WAL) managed by PocketBase | Zero ops |
| Schema | Collections defined in Go migrations (`migrations/`, `migratecmd` with automigrate in dev) | Schema in git, reviewable |
| Business logic | Event hooks (`app.OnRecordCreate(...)`) and custom routes (`se.Router.GET(...)`) | Logic stays server-side |
| Access control | Collection API rules (filter expressions) | Enforced for every API call |
| Files | Local storage or S3-compatible (configured in settings) | Uploads with thumbnails |
| Clients | Official JS SDK (`pocketbase`) or Dart SDK | Typed calls, realtime, auth store |
| Backups | Built-in backups to S3 + cron, or Litestream on `pb_data/data.db` | Point-in-time restore |
| Testing | `testing` with `tests.NewTestApp` and `tests.ApiScenario` | Real app and DB per test |
| Lint | golangci-lint v2 | Zero issues |
| Deploy | Single binary in a small container, `pb_data/` on a volume, Caddy for TLS | One process |

## Project layout

```
main.go                       pocketbase.New(), register migrations, hooks and routes, app.Start()
migrations/                   Go migrations: 1700000000_create_orders.go … (collections, fields, rules, indexes)
internal/
  hooks/                      one file per collection's hooks (orders_hooks.go): validation, side effects
  routes/                     custom endpoints, one area per file (reports.go)
  domain/                     plain Go rules used by hooks and routes; no PocketBase imports
  jobs/                       cron jobs registered with app.Cron()
pb_data/                      runtime data (DB, uploads, backups); git-ignored, mounted volume
pb_public/                    static frontend served by PocketBase (optional)
```

Dependency direction: `main → hooks, routes, jobs → domain`. Hooks and routes translate PocketBase records to domain
values; `domain` never imports PocketBase.

## Conventions

- The schema changes only through Go migrations; automigrate is on in development, and the generated migration is reviewed before committing.
- Every collection has explicit API rules (list/view/create/update/delete); an empty rule means public, `nil` means admins only: set them deliberately.
- Validation that the field options cannot express lives in `OnRecordCreate/Update` hooks calling `domain`.
- Custom routes use `apis.RequireAuth()` (or a role check) and return errors with `e.BadRequestError`/`NotFoundError`.
- Side effects that can fail (emails, webhooks) run after the record is saved (`...Execute` success hooks) or in a job, not before the write.
- Pin the PocketBase version; read its changelog before upgrading (pre-1.0, breaking changes happen).

## Commands

| Task | Command |
| --- | --- |
| Run | `go run . serve --dev` (admin UI at `/_/`) |
| Build | `CGO_ENABLED=0 go build -o bin/app .` |
| Test | `go test ./...` |
| New migration | `go run . migrate create add_orders_status` |
| Apply migrations | `./bin/app migrate up` |
| Lint | `golangci-lint run` |
| Format | `gofmt -w .` |
| Superuser | `./bin/app superuser upsert admin@example.com <password>` |

## Testing

- Domain rules: plain unit tests.
- API rules and hooks: `tests.ApiScenario` against a test app with fixture data (`tests.NewTestApp(testDataDir)`), one scenario per allowed and denied case.
- Migrations: a test that applies all migrations to an empty DB and checks the collections exist.

## Quality gates

- `gofmt` clean, golangci-lint zero issues, `go test ./...` green.
- Every collection has tests that an anonymous and a wrong user are denied.

## Dependencies

- PocketBase and the standard library; JS/Dart SDK on clients.
- Do NOT use: direct SQL writes that bypass PocketBase's record APIs (hooks and rules would not run), a second database for the same data, editing the schema only in the admin UI without a migration, exposing `/_/` publicly without a strong superuser password and IP limits.

## Rules for agents

- Never change collections in the admin UI alone; every schema change is a Go migration in `migrations/`.
- Every new collection gets explicit API rules and tests for allowed and denied access.
- Keep business rules in `internal/domain`; hooks and routes only translate and call them.
- Never bypass the record APIs with raw SQL writes.
- Custom routes always check auth explicitly.
- Never commit `pb_data/`; it is runtime state on a volume.
- Pin the PocketBase version in `go.mod`; upgrades are their own change with the changelog read.
- Backups must be configured (built-in to S3 or Litestream) before the first real user.
