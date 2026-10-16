<!-- name: Go workers (River) -->
<!-- desc: Go background jobs on Postgres with River: transactional enqueue, idempotent jobs, retries, periodic jobs -->

# STACK.md: Go workers (River)

## Summary

Background processing in Go with River, a job queue stored in PostgreSQL. Jobs are enqueued in the same transaction as
the data change that causes them (no lost or phantom jobs), workers run them with retries and exponential backoff, and
periodic jobs replace cron. Every job is idempotent: it can run twice without double effects. Hexagonal layout: workers
are adapters that call application services.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Go 1.25+ | Concurrency, one binary |
| Queue | `github.com/riverqueue/river` + `riverdriver/riverpgxv5` | Postgres-backed, transactional enqueue, retries, unique jobs |
| Database | PostgreSQL 16 | The queue and the data in one place |
| DB access | `jackc/pgx/v5` (pgxpool) + `sqlc` | Type-safe SQL |
| Migrations | `goose` for app tables + `river migrate-up` for River's tables | Both versioned |
| Admin UI | `riverui` (optional) | Inspect, retry and cancel jobs |
| Config | env → typed struct (`caarlos0/env/v11`) | Validated at startup |
| Logging | `log/slog` with job id/kind/attempt attributes | Every log line traceable to a job |
| Testing | `testing`, `rivertest`, `testcontainers-go` | Assert enqueued jobs, run workers in tests |
| Lint | golangci-lint v2 | One config |
| Deploy | Worker binary separate from the API binary (same image) | Scale workers independently; see the deploy add-on |

## Project layout

```
cmd/
  api/main.go                         enqueues jobs (river.Client with no workers started, InsertOnly)
  worker/main.go                      config → pool → river.NewClient(workers, queues, periodic jobs) → Start → graceful Stop
internal/
  config/config.go
  jobs/
    workers.go                        river.NewWorkers() + AddWorker for each worker (the registry)
    queues.go                         queue names and their MaxWorkers
    periodic.go                       periodic jobs (river.PeriodicJob with schedules)
  invoices/
    invoice.go                        entity
    service.go                        use cases (IssueInvoice…) — called by API handlers and by workers
    repository.go                     port
    send_invoice_job.go               SendInvoiceArgs (Kind(), InsertOpts) + SendInvoiceWorker (Work)
    send_invoice_job_test.go
  email/
    sender.go                         port; smtp/provider implementation in its own file
  postgres/                           repositories (sqlc)
migrations/
```

Dependency direction: `worker → service → ports ← adapters`. Job args are small serializable structs; workers resolve
dependencies through constructor injection, never globals.

## Conventions

- Enqueue inside the transaction that changes the data: `client.InsertTx(ctx, tx, args, opts)`.
- Job args carry IDs, not whole objects; the worker loads fresh state and checks whether the work is still needed.
- Every job is idempotent: use unique jobs (`UniqueOpts{ByArgs: true, ByPeriod: …}`) and an idempotency key on external calls.
- Each worker sets `Timeout()` and a sane `MaxAttempts`; transient errors return `err` (retry with backoff), permanent ones `river.JobCancel(err)`, waiting ones `river.JobSnooze(d)`.
- Workers respect `ctx` cancellation; the worker process stops with `client.Stop(ctx)` on SIGTERM so running jobs finish or get retried.
- Queues are named by workload (`default`, `email`, `reports`) with explicit concurrency.
- New job = args struct + worker in the feature folder → register in `jobs/workers.go` → enqueue from the service → tests.

## Commands

| Task | Command |
| --- | --- |
| Run worker | `go run ./cmd/worker` |
| Run API | `go run ./cmd/api` |
| River migrations | `river migrate-up --database-url "$DATABASE_URL"` |
| App migrations | `goose -dir migrations postgres "$DATABASE_URL" up` |
| Generate | `sqlc generate` |
| Test | `go test -race ./...` |
| Lint | `golangci-lint run` |
| Format | `gofmt -w .` |

## Testing

- Services: assert the right job was enqueued with `rivertest.RequireInserted`/`RequireInsertedTx`.
- Workers: call `Work` with a constructed `river.Job` and faked ports; cover success, transient error (retry), permanent error (cancel) and the "already done" path.
- Idempotency test: running the same job twice produces one effect.
- Integration: a real Postgres (testcontainers) with River migrated; insert a job and wait for completion.

## Quality gates

- `gofmt`, `go vet`, `golangci-lint run` zero issues; `go test -race ./...` passes.
- Every registered worker has tests; every job kind is listed in `jobs/workers.go` (a test checks registration).
- sqlc output up to date; migrations apply from scratch.

## Dependencies

- Allowed: the table above.
- Do NOT use: a second queue (Redis/asynq, RabbitMQ) without a decision record, goroutines fired from HTTP handlers for background work, cron inside the API process, `time.Sleep` retries.

## Rules for agents

- Never enqueue a job outside the transaction that produced its reason, when one exists.
- Every worker is idempotent and loads fresh state by ID; never trust stale args.
- Distinguish errors: retryable → return err; permanent → `river.JobCancel`; not yet → `river.JobSnooze`.
- Every worker sets a timeout and honours `ctx` cancellation.
- Never start goroutines for background work in handlers; enqueue a job.
- External calls from jobs carry an idempotency key derived from the job.
- Register every new worker in `jobs/workers.go` and test it.
- Keep job args small and backwards compatible: a deployed worker must still decode args enqueued by the previous version.
