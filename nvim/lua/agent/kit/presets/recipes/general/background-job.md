<!-- name: Background job -->
<!-- desc: a job with retries, backoff, idempotency, status, dead-letter handling, logging and tests -->
<!-- for: server -->
<!-- input: name | Name of the job (e.g. send invoice, rebuild thumbnails) -->
<!-- input: does | What it does and when it is enqueued (one or two sentences) -->

# Recipe: the {{name}} job

{{does}}

## Make

- The job `{{name_pascal}}` with the queue STACK.md's Background jobs row names; if none, the simplest the stack has (a table-backed queue, the framework's task system, a language worker) and no new service just for this.
- A handler that takes a small payload (ids, not whole objects), loads what it needs and does the work; the code that enqueues it, at the place where {{does}} starts.
- Retries with exponential backoff and jitter, a maximum number of attempts, and a separate failure for errors that must not be retried (bad payload, record gone).
- Idempotency: running it twice has the effect of running it once (a unique key, a status check, or an upsert).
- Status the project can read (queued, running, succeeded, failed) and a dead-letter place for jobs out of attempts, with a way to list and requeue them.
- A timeout per run, and structured logs with the job id, attempt and duration.

## Rules

- The handler never holds a transaction or a lock across the whole run; side effects (email, payment calls) come after the state that guards them is saved.
- Failures log the cause without secrets or personal data.
- Settings (attempts, backoff, timeout, concurrency) are named constants or env values, not magic numbers.
- Follow the existing jobs: folder, naming, registration.

## Tests

- The handler succeeds with a valid payload and has the effect once when run twice.
- A retryable error is retried with growing delays; a permanent error goes straight to failed; after the last attempt the job lands in the dead letter.
- The enqueue site enqueues exactly one job with the right payload (a fake queue or the in-memory driver).
