<!-- name: Python HTTP endpoint -->
<!-- desc: an endpoint with request/response models, the service behind it, and pytest tests -->
<!-- for: python+server -->
<!-- input: name | What the endpoint does (e.g. create order, list invoices) -->
<!-- input: route | Method and path (e.g. POST /orders) -->

# Recipe: {{name}} ({{route}})

## Make

- The endpoint `{{route}}` in the framework STACK.md names (FastAPI router, Django view/URL, Flask blueprint), registered with the others.
- Request and response models (Pydantic, or the framework's serializers) with validation of every field.
- A service function `{{name_snake}}` with the rule, independent of the framework; data through the project's repository or ORM session.

## Rules

- Type hints everywhere; errors mapped once to status codes (422/400 invalid, 404, 409, 500 without internals).
- Dependencies (session, current user) through the framework's injection, as the existing endpoints do.

## Tests

- pytest with the framework's test client: the happy path, invalid input, each service error; the service alone with a fake repository.
