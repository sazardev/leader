<!-- name: Python Flask -->
<!-- desc: minimal WSGI app: Flask, SQLAlchemy 2, Alembic, uv, ruff, pytest -->
<!-- for: backend -->

# STACK.md: Python Flask

## Summary

A minimal HTTP app in Python. Flask 3 holds the routes; SQLAlchemy 2 (typed `Mapped[]` models) talks to Postgres; Alembic migrates. Hexagonal layout by feature: blueprints and repositories are adapters, the domain is plain dataclasses with no Flask imports. The smallest framework that still separates concerns.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Python 3.12+ | Modern typing |
| Packaging | `uv` (`pyproject.toml` + `uv.lock`) | Fast, reproducible |
| HTTP | Flask 3 + `gunicorn` | Minimal, WSGI, mature |
| Validation | `marshmallow` (request schemas) | Input parsing separated from SQLAlchemy |
| Database | PostgreSQL 16 | Relational, transactional |
| DB access | SQLAlchemy 2.0 + `psycopg` | Typed models, explicit sessions |
| Migrations | Alembic (autogenerate, reviewed by hand) | Standard for SQLAlchemy |
| Settings | `pydantic-settings` | Env → typed settings |
| Logging | `structlog` (JSON in prod) | Structured |
| Auth | Session cookies (`itsdangerous`) or JWT (`pyjwt`) | Same primitives as FastAPI |
| Testing | `pytest` + `httpx` + `testcontainers[postgres]` | Real DB in integration |
| Lint / format | `ruff check` + `ruff format` | One fast tool |
| Types | `mypy --strict` | Types are enforced |

## Project layout

```
pyproject.toml                     dependencies, ruff, mypy, pytest config
migrations/                        Alembic env.py + versions/
src/app/
  __init__.py                      create_app(): blueprints, middleware, error handlers
  config.py                        Settings (pydantic-settings)
  shared/
    errors.py                      DomainError + NotFound, Conflict, InvalidState
    db.py                          engine, Session, unit of work
    http_errors.py                 DomainError → HTTP status + problem JSON, in ONE place
  <feature>/
    domain.py                      entity (dataclass) + invariants
    ports.py                       OrderRepository Protocol
    services.py                    one use case per function: place_order(session, input)
    models.py                      SQLAlchemy ORM models of the feature
    repository.py                  implements the Protocol; maps models ↔ entities
    routes.py                      Blueprint: endpoints → use cases
    schemas.py                     marshmallow request/response schemas
tests/
  unit/<feature>/                  use cases with fakes
  integration/<feature>/           repositories and API against Postgres
  conftest.py
```

Dependency direction: `routes → services → domain`, `repository → domain`.

## Conventions

- One module = one responsibility; modules over ~300 lines are split. `snake_case` modules, `PascalCase` classes.
- Routes are thin: marshmallow schema in, one service, schema out. No SQLAlchemy in routes.
- Domain entities are dataclasses, not ORM models; repositories map between them.
- One `Session` per request via `g`; commits happen in the unit of work.
- Errors: raise `DomainError` subclasses; error handlers map them; never raise `HTTPException` outside `routes.py`.

## Commands

| Task | Command |
| --- | --- |
| Install | `uv sync` |
| Dev | `uv run flask --app app run` |
| Run | `uv run gunicorn app:create_app()` |
| Test | `uv run pytest` |
| Single test | `uv run pytest tests/unit/orders/test_place.py -k happy_path` |
| Lint | `uv run ruff check .` |
| Format | `uv run ruff format .` |
| Migration | `uv run alembic revision --autogenerate -m "<change>"` then `uv run alembic upgrade head` |

## Testing

- Services: pytest unit tests with in-memory fake repositories.
- API: `pytest` with the Flask test client; repositories against Postgres in testcontainers.
- Factories for test data (plain functions), no shared hidden state.
- A bug fix starts with a failing test; domain and services coverage above 85%.

## Quality gates

- `ruff check` and `ruff format --check` clean.
- `mypy --strict src` with zero errors.
- `pytest` passes in CI; `alembic check` reports no pending model changes.
- `uv lock --check` passes.

## Dependencies

- Standard library first; then the table above. Every new dependency is added with `uv add` and justified in the PR.
- Do NOT use: Flask-SQLAlchemy magic alongside raw SQLAlchemy; Django alongside Flask; synchronous drivers in async code.

## Rules for agents

- Type every function; never add `# type: ignore` without the error code and a reason.
- Never import Flask, marshmallow or SQLAlchemy in `domain.py`.
- Never use the session or ORM models outside `repository.py` and the unit of work.
- Never raise `HTTPException` from services or domain; raise `DomainError` subclasses.
- Every schema change has an Alembic migration, reviewed by hand; never edit an applied one.
- Run `ruff format`, `ruff check`, `mypy` and `pytest` before declaring a change done.
- Add dependencies only with `uv add`; never edit `uv.lock` by hand.
