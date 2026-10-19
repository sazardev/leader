<!-- name: Inngest -->
<!-- desc: event-driven durable functions for TypeScript: steps, retries, sleeps and cron without a queue to run -->
<!-- for: ts js node bun !mobile -->

## Stack

| Background jobs | Inngest (event-driven durable functions with `step.run`, retries, `step.sleep`, cron triggers) | Multi-step workflows and serverless-friendly jobs without running workers |

## Project layout

```
src/inngest/client.ts          the Inngest client with typed event schemas
src/inngest/functions/         one file per function (trigger, steps)
src/app/api/inngest/route.ts   the serve handler exposing the functions (path depends on the framework)
.env.example                   INNGEST_EVENT_KEY, INNGEST_SIGNING_KEY (placeholders)
```

## Conventions

- The app sends events (`inngest.send({ name: "order/paid", data: { orderId } })`) and functions react to them; business code never calls a function directly.
- Each function is a list of `step.run` calls: a step is retried alone and its result is memoized, so code outside steps must be deterministic and side-effect free.
- Event payloads are small and typed; steps load current data by id.
- Steps are idempotent; configure `retries`, `concurrency` and `idempotency` per function where it matters.
- Waiting uses `step.sleep`, `step.sleepUntil` or `step.waitForEvent`, never a timer in a process.

## Commands

| Dev server | `npx inngest-cli@latest dev` |

## Testing

- Business logic lives in plain service functions tested alone; functions are tested with `@inngest/test` or by running the Dev Server and sending events.

## Rules for agents

- Never put side effects outside `step.run`; they would repeat on every replay.
- Always keep the signing key on the server and verify requests through the serve handler.
- Never send secrets or personal data inside events; they are stored and visible in the dashboard.
