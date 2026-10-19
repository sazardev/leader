<!-- name: River -->
<!-- desc: Postgres-backed job queue for Go: transactional enqueue, typed workers, retries, periodic jobs -->
<!-- for: go -->

## Stack

| Background jobs | River (`riverqueue/river`, jobs stored in PostgreSQL, typed workers, `pgx`) | Jobs are enqueued in the same transaction as the data, no Redis to run |

## Project layout

```
internal/jobs/                 job args structs, workers (river.Worker[T]), client setup
migrations/                    River's own tables, applied with `river migrate-up`
cmd/worker/                    entry point of the worker process (or started from the same binary)
```

## Conventions

- Job args are a struct with `Kind() string` and only ids and small values; the worker loads current data itself.
- Enqueue with `client.InsertTx` inside the transaction that changes the data, so a job exists only if the change committed.
- Workers are idempotent; set `MaxAttempts` and use `river.JobSnooze` or `river.JobCancel` for expected conditions instead of returning an error.
- Queues and their `MaxWorkers` are declared in the client `Config`; slow work gets its own queue.
- Periodic work uses `river.NewPeriodicJob` in the client config, not `time.Ticker` goroutines.
- Shutdown calls `client.Stop` with a context so running jobs finish before exit.

## Commands

| Migrate jobs | `river migrate-up --database-url "$DATABASE_URL"` |
| Worker | `go run ./cmd/worker` |

## Testing

- Use `rivertest` (`RequireInserted`, `Worker`) with a real PostgreSQL and a transaction per test.

## Rules for agents

- Never enqueue a job outside the transaction when it depends on a row written in that transaction.
- Never put secrets or personal data in job args; they are stored in plain JSON.
- Every worker must respect the `context.Context` it receives.
