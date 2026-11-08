<!-- name: Python Django -->
<!-- desc: Django + DRF on PostgreSQL: admin, ORM, migrations, channels for realtime -->
<!-- for: backend -->

# STACK.md: Python Django

## Summary

A batteries-included API in Python. Django provides the ORM, migrations and admin; Django REST Framework exposes the models as an API; Channels adds websockets when needed. Hexagonal layout by app: apps are the bounded contexts, with services between views and models. Everything is typed where it pays off (mypy with the Django stubs).

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Python 3.12+ | Modern typing, fast iteration |
| Packaging | `uv` (`pyproject.toml` + `uv.lock`) | Fast, reproducible |
| Framework | Django 5 + Django REST Framework | ORM, migrations, admin, auth |
| API | DRF ViewSets + routers | Consistent CRUD, OpenAPI via `drf-spectacular` |
| Database | PostgreSQL 16 | Relational, transactional |
| DB access | Django ORM (`QuerySet`, `select_related`, `prefetch_related`) | Transactions and migrations built in |
| Migrations | `makemigrations` + `migrate` | Forward-only, reviewed by hand |
| Settings | `django-settings` from env (`pydantic-settings`) | Env → typed settings, validated at startup |
| Logging | `structlog` (JSON in prod) | Structured |
| Auth | Session auth (Django) + JWT (`djangorestframework-simplejwt`) | Same users for admin and API |
| Testing | `pytest` + `pytest-django` + `factory_boy` + `testcontainers[postgres]` | Real DB in integration |
| Lint / format | `ruff check` + `ruff format` | One fast tool |

## Project layout

```
pyproject.toml                     dependencies, ruff, pytest config
manage.py
config/
  settings.py                      env → Settings
  urls.py                          includes each app's urls
  asgi.py / wsgi.py
apps/<context>/
  models.py                        ORM models of the app
  serializers.py                   DRF serializers (input/output)
  views.py                         ViewSets: decode → service → encode
  services.py                      use cases, transactions
  urls.py                          router registrations of the app
  tests/                           unit + integration per service
migrations/                        per-app Django migrations
```

Dependency direction: `views → services → models`. Services never import DRF or Django HTTP.

## Conventions

- One app = one bounded context; apps over ~500 lines of `services.py` are split per use case.
- Serializers are the contract: views never build `Response` dicts by hand; `drf-spectacular` generates the OpenAPI from them.
- Every write runs in `transaction.atomic()` through a service; views never call `Model.objects.create` directly.
- N+1 is a bug: `select_related`/`prefetch_related` are the default, verified with `assertNumQueries`.
- Settings come from the environment; no secrets in `settings.py`; `.env.example` documents them.

## Commands

| Task | Command |
| --- | --- |
| Install | `uv sync` |
| Dev | `uv run python manage.py runserver` |
| Test | `uv run pytest` |
| Single test | `uv run pytest apps/orders/tests/test_place.py -k happy_path` |
| Lint | `uv run ruff check .` |
| Format | `uv run ruff format .` |
| Migrate makemigrations | `uv run python manage.py makemigrations` |
| Migrate | `uv run python manage.py migrate` |
| Schema | `uv run python manage.py spectacular --file api/openapi.yaml` |

## Testing

- Services: pytest unit tests with the ORM replaced by fakes; no DB.
- Views and repositories: integration tests against Postgres in testcontainers; migrations applied once, each test in a rolled-back transaction (`pytest-django` `transaction=True` where needed).
- Serializers: a test loads `api/openapi.yaml` and checks every route is registered.
- A bug fix starts with a failing test; `apps/*/services.py` coverage above 85%.

## Quality gates

- `ruff check` and `ruff format --check` clean.
- `mypy` (with the Django plugin) reports zero errors on `apps/`.
- `pytest` passes in CI; `makemigrations --check` reports no pending model changes.
- `uv lock --check` passes.

## Dependencies

- Standard library first; then the table above. Every new dependency is added with `uv add` and justified in the PR.
- Do NOT use: raw SQL in views; GraphQL alongside DRF without a reason; Celery in the request path (use the Background jobs add-on).

## Rules for agents

- Change `serializers.py` first for any API change, then regenerate the schema; never hand-edit `api/openapi.yaml`.
- Never put business rules in views or serializers; they live in `services.py` and model invariants.
- Every query goes through the ORM with parameters; never build SQL with string concatenation.
- Never log secrets, tokens or full request bodies; log the request id.
- Add a migration for every model change; never edit an applied migration; every migration is reversible or says why not.
- Run `ruff format`, `ruff check`, `mypy` and `pytest` before declaring a change done.
- Add dependencies only with `uv add`; never edit `uv.lock` by hand.
