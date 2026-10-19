<!-- name: Go HTTP endpoint -->
<!-- desc: a handler, the service method behind it, its route and handler + service tests -->
<!-- for: go+server -->
<!-- input: name | What the endpoint does, as a verb and a noun (e.g. create order, list invoices) -->
<!-- input: route | Method and path (e.g. POST /orders) -->

# Recipe: {{name}} ({{route}})

## Make

- The handler `{{name_pascal}}` for `{{route}}` in the transport/HTTP package STACK.md's layout names, on the router the project uses (net/http `ServeMux` patterns, chi, Echo, Fiber, Huma…).
- A request type decoded and validated at the edge (required fields, formats, limits) and a response type; the JSON field names in the project's style.
- The service (use case) method it calls, in the application/service package, taking and returning domain types; the handler holds no business rule.
- The route registered where the others are, with the project's middleware (auth, logging, request id).

## Rules

- Errors map in one place to status codes: invalid input 400 (with which field), not found 404, conflict 409, anything else 500 without internals in the body.
- `context.Context` flows from the request to the service and the repository.
- Follow the existing handlers: naming, error helper, how they write JSON.

## Tests

- Handler tests with `httptest`: the happy path, invalid input, and each domain error the service can return (a fake service).
- Service tests for the rule it applies (a fake or in-memory repository).
