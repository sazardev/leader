<!-- name: Sentry -->
<!-- desc: error tracking and performance monitoring with releases and source maps / debug symbols -->
<!-- for: all -->
<!-- default: mobile react-vite solid preact sveltekit nuxt nextjs -->

## Stack

| Errors | Sentry SDK for the platform, release = git SHA, source maps / debug symbols uploaded in CI | Every unhandled error with stack trace, release and context |

## Conventions

- DSN and environment come from configuration; Sentry is disabled when no DSN is set (local and tests).
- `release` is the git SHA and `environment` is dev/staging/prod.
- `beforeSend` scrubs tokens, passwords and personal data; `sendDefaultPii` stays off.
- Expected errors (validation, not found) are not reported; unexpected ones always are.

## Rules for agents

- Never swallow an unexpected error without reporting it.
- Never attach request bodies, tokens or personal data to events.
