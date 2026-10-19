<!-- name: SQLAlchemy -->
<!-- desc: SQLAlchemy 2.0 typed models and sessions with Alembic migrations for Python services -->
<!-- for: python -->

## Stack

| Data access | SQLAlchemy 2.0 (typed `Mapped[]` models, one session per request, Alembic migrations) | The standard Python ORM and query builder, explicit and well tested |

## Project layout

```
src/app/db/base.py             DeclarativeBase and naming convention for constraints
src/app/db/models/             one module per aggregate
src/app/db/session.py          engine and session factory (from DATABASE_URL)
alembic.ini                    Alembic configuration
migrations/                    Alembic revisions (`env.py` imports the models' metadata)
```

## Conventions

- Models use 2.0 style: `Mapped[...]` and `mapped_column(...)`, with a metadata naming convention so constraint names are stable.
- One `Session` per request or task, closed at the end (dependency or context manager); never a global session.
- Queries use `select()` and `session.execute()`; avoid lazy-loading in loops, use `selectinload`/`joinedload`.
- Autogenerate migrations with Alembic and read them before committing.
- Async apps use `create_async_engine` with an async driver (`asyncpg`, `aiosqlite`) everywhere, not a mix.

## Commands

| Generate migration | `alembic revision --autogenerate -m "<change>"` |
| Migrate | `alembic upgrade head` |
| Rollback | `alembic downgrade -1` |

## Rules for agents

- Never build SQL with f-strings; use bound parameters or `text()` with `:name` binds.
- Never edit an applied Alembic revision; add a new one.
- Never share a session between threads or concurrent tasks.
