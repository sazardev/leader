<!-- name: Performance -->
<!-- desc: measure first, budgets, no N+1, paginate and stream, caches with invalidation, timeouts everywhere -->

### Performance

- **Measure first**: optimize only with a profile, benchmark or production metric that shows the problem; record the before and after numbers.
- **Budgets**: explicit targets (p95 latency per endpoint, bundle size, startup time, memory) checked in CI or monitoring.
- **No N+1**: data for a list is loaded in one query or a batch (joins, `IN`, dataloaders); queries inside loops are bugs.
- **Bounded work**: every list is paginated, large payloads are streamed, unbounded reads (whole tables, whole files) are not allowed.
- **Indexes** match the queries; every new query is checked with its plan on realistic data.
- **Caching** has an owner, a key, a TTL and an invalidation strategy; never cache without knowing how it becomes stale.
- **Timeouts everywhere**: every network call, query and lock has a timeout and cancellation propagates (context, abort signals).
- **Async for slow work**: emails, reports and third-party calls that the user need not wait for go to a queue.
- **No premature optimization**: clear code first; micro-optimizations need a measurement that justifies the lost readability.
- Review check: no new query in a loop, no unbounded list, no network call without a timeout.
