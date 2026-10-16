<!-- name: Prometheus + Grafana -->
<!-- desc: /metrics endpoint scraped by Prometheus, RED dashboards and alerts in Grafana -->
<!-- for: server backend selfhosted !mobile -->

## Stack

| Observability | Prometheus metrics on `GET /metrics`, Prometheus scrapes, Grafana dashboards and alerts | Standard self-hostable monitoring with a huge ecosystem |

## Conventions

- RED metrics for every endpoint: request rate, errors, duration histogram (`http_server_request_duration_seconds`).
- Metric names in snake_case with unit suffixes (`_seconds`, `_bytes`, `_total`).
- `/metrics` is not exposed publicly (internal port or network only).
- Every alert links to a runbook and fires on symptoms users feel (error rate, latency), not on causes.

## Rules for agents

- Never use unbounded label values (user ids, raw paths, emails).
- A new endpoint or background job gets its RED metrics in the same change.
