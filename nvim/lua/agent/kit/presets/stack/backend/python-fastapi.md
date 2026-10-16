<!-- name: Python FastAPI -->
<!-- desc: async API: FastAPI, Pydantic v2, SQLAlchemy 2 async + Alembic, uv, ruff, mypy strict, pytest -->

# STACK.md: Python FastAPI

## Summary

An async HTTP API in Python. FastAPI with Pydantic v2 validates input and generates OpenAPI; SQLAlchemy 2 (async,
typed `Mapped[]` models) talks to Postgres; Alembic migrates. Hexagonal layout by feature: routers and repositories are
adapters, the domain is plain dataclasses with no framework imports. Everything is type-checked strictly.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Python 3.12+ | Modern typing (`type` aliases, generics syntax) |
| Packaging | `uv` (`pyproject.toml` + `uv.lock`) | Fast, reproducible, manages Python versions |
| HTTP | FastAPI + Uvicorn (`uvicorn[standard]`) | Async, typed, OpenAPI for free |
| Validation | Pydantic v2 | Request/response schemas and settings |
| Settings | `pydantic-settings` | Env → typed settings, validated at startup |
| Database | PostgreSQL 16 | Relational, transactional |
| DB access | SQLAlchemy 2.0 async + `asyncpg` | Typed models, explicit sessions |
| Migrations | Alembic (autogenerate, reviewed by hand) | Standard for SQLAlchemy |
| Logging | `structlog` (JSON in prod) | Structured, context vars per request |
| Auth | OAuth2/JWT with `pyjwt`, passwords with `argon2-cffi` | Standard primitives |
| Testing | `pytest` + `pytest-asyncio` (or `anyio`) + `httpx.AsyncClient` + `testcontainers[postgres]` | Fast unit tests, real DB in integration |
| Lint / format | `ruff check` + `ruff format` | One fast tool |
| Types | `mypy --strict` (or `pyright` strict) | Types are enforced, not decorative |

## Project layout

```
pyproject.toml                     dependencies, ruff, mypy, pytest config
alembic.ini
migrations/                        Alembic env.py + versions/
src/app/
  main.py                          create_app(): routers, middleware, exception handlers, lifespan
  config.py                        Settings (pydantic-settings)
  container.py                     composition root: engine, session factory, repositories, services
  shared/
    errors.py                      DomainError + NotFound, Conflict, InvalidState
    db.py                          engine, async_sessionmaker, unit of work
    http_errors.py                 DomainError → HTTP status + problem JSON, in ONE place
  <feature>/
    domain/
      order.py                     entity (dataclass) + invariants — no FastAPI/SQLAlchemy imports
      ports.py                     OrderRepository Protocol
    application/
      place_order.py               one use case per file: class with __call__ / execute
    infrastructure/
      models.py                    SQLAlchemy ORM models of the feature
      sqlalchemy_order_repository.py  implements the Protocol; maps models ↔ entities
    api/
      router.py                    APIRouter: endpoints → use cases
      schemas.py                   Pydantic request/response models
      deps.py                      FastAPI Depends providers for this feature
tests/
  unit/<feature>/                  use cases with fakes
  integration/<feature>/           repositories and API against Postgres
  conftest.py
```

Dependency direction: `api → application → domain`, `infrastructure → domain`. `domain` imports only the standard library.

## Conventions

- One module = one responsibility; modules over ~300 lines are split. `snake_case` modules, `PascalCase` classes.
- Every function and method is fully typed; no implicit `Any`. Ports are `typing.Protocol`.
- Routers are thin: Pydantic schema in, one use case, schema out. No SQLAlchemy in routers.
- Domain entities are dataclasses (or attrs), not ORM models and not Pydantic models; repositories map between them.
- One `AsyncSession` per request via a dependency; commits happen in the unit of work, not in repositories.
- All IO is async; never call blocking libraries in the event loop (use `anyio.to_thread.run_sync` if unavoidable).
- Errors: raise `DomainError` subclasses; exception handlers map them; never raise `HTTPException` outside `api/`.
- New feature = domain + port → use case + unit test → model + repository + migration → schemas + router → include router in `main.py`.

## Commands

| Task | Command |
| --- | --- |
| Install | `uv sync` |
| Dev | `uv run fastapi dev src/app/main.py` |
| Run | `uv run uvicorn app.main:app --host 0.0.0.0 --port 8000` |
| Test | `uv run pytest` |
| Single test | `uv run pytest tests/unit/orders/test_place_order.py -k happy_path` |
| Lint | `uv run ruff check .` |
| Format | `uv run ruff format .` |
| Types | `uv run mypy src` |
| Migration | `uv run alembic revision --autogenerate -m "<change>"` then `uv run alembic upgrade head` |

## Testing

- Use cases: pytest unit tests with in-memory fake repositories; no database, no app.
- API: `httpx.AsyncClient(transport=ASGITransport(app=app))` with dependencies overridden via `app.dependency_overrides`.
- Repositories and migrations: integration tests against Postgres in testcontainers; `alembic upgrade head` once per session, a rolled-back transaction per test.
- Factories for test data (plain functions or `polyfactory`), no shared fixtures with hidden state.
- A bug fix starts with a failing test; domain and application coverage above 85% (`pytest-cov`).

## Quality gates

- `ruff check` (rules: E, F, I, B, UP, SIM, RUF, S, ASYNC, PL at least) and `ruff format --check` clean.
- `mypy --strict src` with zero errors.
- `pytest` passes in CI; `alembic check` reports no pending model changes.
- `uv lock --check` passes; `pip-audit` (via `uvx pip-audit`) reports no known vulnerabilities.

## Dependencies

- Standard library first; then the table above. Every new dependency is added with `uv add` and justified in the PR.
- Do NOT use: Flask/Django mixed in; SQLAlchemy 1.x query style (`session.query`); synchronous DB drivers (`psycopg2`) in async code; `requests` (use `httpx`); Poetry/pip-tools alongside uv; Pydantic models as ORM entities (SQLModel) in the domain.

## Rules for agents

- Type every function; never add `# type: ignore` without the error code and a reason.
- Never import FastAPI, Pydantic or SQLAlchemy in `domain/`.
- Never use the session or ORM models outside `infrastructure/` and the unit of work.
- Never call blocking IO (`time.sleep`, `requests`, sync drivers) inside `async def`.
- Never raise `HTTPException` from application or domain code; raise `DomainError` subclasses.
- Every schema change has an Alembic migration, reviewed by hand (autogenerate misses things); never edit an applied one.
- Run `ruff format`, `ruff check`, `mypy` and `pytest` before declaring a change done.
- Add dependencies only with `uv add`; never edit `uv.lock` by hand.
