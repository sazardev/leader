<!-- name: OpenTelemetry -->
<!-- desc: traces, metrics and logs with the OTel SDK, exported over OTLP to a collector -->
<!-- for: server backend fullstack selfhosted !mobile -->
<!-- default: backend selfhosted -->

## Stack

| Observability | OpenTelemetry SDK (traces + metrics, logs correlated by trace id), OTLP to an OpenTelemetry Collector | Vendor-neutral: switch backends (Grafana, Honeycomb, Jaeger…) by config |

## Conventions

- Instrumentation libraries for the HTTP server, HTTP client and database driver; manual spans only around meaningful business operations.
- Exporter configured by the standard env vars (`OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_SERVICE_NAME`, `OTEL_RESOURCE_ATTRIBUTES`); nothing hardcoded.
- Every log line inside a request carries `trace_id` and `span_id`.
- Span and metric attributes never contain secrets or personal data.

## Rules for agents

- New outbound calls (HTTP, DB, queues) use instrumented clients so they appear in traces.
- Never put user data (emails, tokens, payloads) in span attributes or metric labels.
- Metric labels have bounded cardinality: never an id or a raw URL as a label.
