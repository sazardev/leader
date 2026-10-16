<!-- name: Observability -->
<!-- desc: structured logs with request ids, RED/USE metrics, OpenTelemetry traces, health checks, actionable alerts -->

### Observability

- **Structured logs** (JSON in production) with level, message, timestamp and context fields; never interpolate values into the message string.
- **Correlation**: every request/job carries a request id / trace id that appears in all its logs and is propagated to downstream calls.
- **Levels mean something**: error = someone must act, warn = degraded but handled, info = business-relevant events, debug off in production.
- **Metrics**: RED (rate, errors, duration) for every endpoint and consumer, USE (utilization, saturation, errors) for resources and pools.
- **Traces** with OpenTelemetry for requests that cross services, databases or queues; spans named after operations, not URLs with ids.
- **Health endpoints**: liveness (process alive) and readiness (dependencies reachable) are separate and cheap.
- **Alerts are actionable**: on symptoms users feel (error rate, latency SLOs), each with a runbook link; no alerts nobody acts on.
- **Cardinality control**: no user ids, emails or raw URLs as metric labels.
- Review check: a new feature's failure would show up in logs, metrics and traces with enough context to diagnose it without a debugger.
