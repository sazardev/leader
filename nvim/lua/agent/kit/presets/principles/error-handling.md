<!-- name: Error handling -->
<!-- desc: never swallow, wrap with context, domain vs infrastructure errors, map once at the boundary -->
<!-- core: true -->

### Error handling

- **Never swallow**: every error is handled, returned or logged-and-escalated exactly once; empty catch blocks and ignored results are bugs.
- **Wrap with context**: add what was being done (`load order 42: …`) while keeping the original cause inspectable (wrapping, `cause`).
- **Domain errors are types/values** (`ErrOrderNotFound`, `InsufficientFunds`) declared in the core; infrastructure errors stay in adapters and are translated.
- **Map at the boundary, once**: one place turns errors into HTTP status, exit codes or UI messages; no status codes inside business logic.
- **Fail fast at startup**: missing or invalid configuration stops the process with a clear message instead of failing on first use.
- **No exceptions/panics for control flow**: expected outcomes (not found, invalid input) are values; panics only for programmer errors.
- **User-safe messages**: users see what happened and what to do; stack traces, SQL and internal ids go only to logs.
- **Log where handled**, not at every layer: one log entry per failure, with its context and correlation id.
- **Retries** only for transient errors, with backoff, jitter and a limit; never retry non-idempotent operations blindly.
- Review check: no new code path drops an error; every new error type is mapped at the boundary.
