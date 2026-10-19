<!-- name: Rust HTTP endpoint -->
<!-- desc: an Axum/Actix handler, its extractors and error type, the service behind it, and tests -->
<!-- for: rust+server -->
<!-- input: name | What the endpoint does (e.g. create order, list invoices) -->
<!-- input: route | Method and path (e.g. POST /orders) -->

# Recipe: {{name}} ({{route}})

## Make

- The handler `{{name_snake}}` for `{{route}}` on the framework STACK.md names (Axum, Actix Web), with typed extractors (`Json`, `Path`, `State`) and serde request/response types.
- The service function with the rule, independent of the framework.
- The route added to the router where the others are.

## Rules

- One error enum implementing the framework's response trait (`IntoResponse`): validation 400, not found 404, conflict 409, internal 500 without details; `thiserror` when the project uses it.
- No `unwrap()` outside tests.

## Tests

- The router through `tower::ServiceExt::oneshot` (or Actix's test utilities): the happy path, invalid input, each error; the service alone.
