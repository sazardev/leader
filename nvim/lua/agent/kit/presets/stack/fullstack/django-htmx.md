<!-- name: Django + htmx -->
<!-- desc: Django 5 + htmx: apps per bounded context, services/selectors, Postgres, pytest-django, ruff, uv -->

# STACK.md: Django + htmx

## Summary

A server-rendered web application on Django 5 with htmx for interactivity: views return full pages or HTML partials,
no SPA and no JSON API for the UI. Each bounded context is a Django app. Business logic follows the services/selectors
pattern: writes go through service functions, reads through selector functions; views, forms and templates stay thin,
and models hold data and invariants, not workflows.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Python 3.12+ with type hints | |
| Framework | Django 5.1+ | ORM, admin, forms, auth, migrations, security defaults |
| Interactivity | htmx 2 + `django-htmx` (`request.htmx`) | Hypermedia; partial templates |
| Templates | Django templates + `django-template-partials` (optional) | Partials inside the page template |
| Database | PostgreSQL 16 (`psycopg` 3) | |
| Config | `django-environ` (env → settings) | 12-factor |
| Background jobs | Celery + Redis, or `django-tasks`/RQ for small needs | Only when needed |
| Styling | Tailwind CSS (standalone CLI or `django-tailwind-cli`) | |
| Tests | pytest + `pytest-django` + `factory_boy` | Fixtures and factories |
| Lint/format | ruff (lint + format) + mypy with `django-stubs` | |
| Package manager | uv (`pyproject.toml`, `uv.lock`) | Fast, reproducible |
| Server | gunicorn (+ uvicorn workers if async views) + whitenoise for static | |

## Project layout

```
config/
  settings/base.py                 shared settings
  settings/dev.py
  settings/prod.py
  urls.py
  wsgi.py
apps/
  orders/
    models.py                      models: fields, constraints, small invariants
    services.py                    write use cases: order_place(*, user, items) -> Order
    selectors.py                   reads: order_list(*, user, filters) -> QuerySet
    forms.py                       input validation for views
    views.py                       thin: form → service/selector → render page or partial
    urls.py
    admin.py
    templates/orders/
      order_list.html              full page
      partials/order_rows.html     what htmx swaps
    migrations/
    tests/
      factories.py
      test_services.py
      test_selectors.py
      test_views.py
  accounts/
templates/base.html                layout, htmx script, CSRF header
static/
pyproject.toml
uv.lock
```

Dependency direction: `views → forms, services, selectors → models`; apps call another app only through its
`services.py`/`selectors.py`, never its models' internals or views.

## Conventions

- One module = one responsibility: services write, selectors read, views orchestrate HTTP. Split a module past ~300 lines into a package (`services/order_place.py`).
- Services are functions with keyword-only arguments, typed, wrapped in `transaction.atomic` when they write more than one row; they call `full_clean()` before saving.
- Views: `if request.htmx:` render the partial, else the full page; validation errors re-render the form partial with status 422.
- Send the CSRF token for htmx with `hx-headers='{"X-CSRFToken": "{{ csrf_token }}"}'` on `<body>`.
- Avoid N+1: selectors use `select_related`/`prefetch_related`; views never touch related managers in loops.
- Fat models are not the goal: models hold fields, constraints (`Meta.constraints`) and simple properties.
- New feature = model + migration → selectors/services → form → view + URL → page and partial templates → tests.

## Commands

| Task | Command |
| --- | --- |
| Install | `uv sync` |
| Dev server | `uv run python manage.py runserver` |
| Migrations | `uv run python manage.py makemigrations && uv run python manage.py migrate` |
| Tests | `uv run pytest` |
| Lint | `uv run ruff check .` |
| Format | `uv run ruff format .` |
| Type check | `uv run mypy .` |
| Deploy checks | `uv run python manage.py check --deploy` |
| Missing migrations | `uv run python manage.py makemigrations --check --dry-run` |
| CSS | `tailwindcss -i static/src/input.css -o static/css/app.css --watch` |

## Testing

- Services and selectors: pytest with the database (`@pytest.mark.django_db`), data from `factory_boy` factories.
- Views: Django test client; assert status, template used, and that htmx requests (`HTTP_HX_REQUEST="true"`) get the partial.
- Query counts for list views with `django_assert_num_queries`.
- A bug fix starts with a failing test.

## Quality gates

- `ruff check` and `ruff format --check` clean; mypy (with `django-stubs`) clean on `apps/`.
- `makemigrations --check` shows no missing migrations; `check --deploy` clean for prod settings.
- pytest green in CI with coverage on services and selectors.

## Dependencies

- Django's batteries first (forms, auth, admin, messages, caching).
- Allowed: the table above; anything else needs a reason in the PR.
- Do NOT use: Django REST Framework for the UI (htmx renders HTML), a JS framework or bundler for pages, signals for business workflows (call services explicitly), raw SQL with string formatting, `pip` without the lockfile.

## Rules for agents

- Put writes in `services.py` and reads in `selectors.py`; never put business logic in views, forms' `save()` overrides or templates.
- Never use signals to drive business workflows.
- Every htmx endpoint returns a partial for htmx requests and a full page otherwise.
- Every POST is CSRF-protected; never use `csrf_exempt` on user-facing views.
- Every model change ships its migration; never edit an applied migration.
- Use `select_related`/`prefetch_related` in selectors for anything rendered in a list.
- Never call another app's models directly from a view: go through its services/selectors.
- Settings come from the environment; never commit secrets or a `DEBUG = True` production setting.
- Use `uv add` to add dependencies so `uv.lock` stays in sync.
