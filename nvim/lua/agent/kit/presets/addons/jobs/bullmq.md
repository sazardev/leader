<!-- name: BullMQ -->
<!-- desc: Redis-backed job queues for Node and Bun: retries with backoff, delayed and repeatable jobs -->
<!-- for: ts js node bun !mobile -->

## Stack

| Background jobs | BullMQ (Redis-backed queues, a separate worker process, retries with backoff, repeatable jobs) | Reliable async work without blocking requests |

## Project layout

```
src/jobs/queues.ts             one Queue per job family, shared Redis connection options
src/jobs/workers/              one Worker per queue; the processor only calls a service function
src/worker.ts                  entry point of the worker process (separate from the HTTP server)
```

## Conventions

- The worker runs as its own process and container; the web process only adds jobs.
- Job payloads are small, JSON-serializable ids (`{ orderId }`), never whole objects or secrets; the processor loads fresh data.
- Every job is idempotent: a retry or a double delivery must not charge, email or write twice (use a business key or `jobId` for de-duplication).
- Set `attempts`, exponential `backoff`, `removeOnComplete` and `removeOnFail` with a retention limit on every queue.
- Scheduled work uses job schedulers / repeatable jobs defined in code at worker start, not ad-hoc timers.
- Workers handle `SIGTERM` by closing (`worker.close()`) so active jobs finish.

## Commands

| Worker | `npm run worker` |
| Redis up | `docker compose up -d redis` |

## Testing

- Processors are tested as plain functions; one integration test per queue uses a real Redis and drains it.

## Rules for agents

- Never run heavy work inside the HTTP request when a job fits.
- Never put personal data or secrets into job payloads or logs.
- Every `Worker` has an `error` / `failed` listener that reports the failure.
