<!-- name: Celery -->
<!-- desc: distributed task queue for Python with Redis or RabbitMQ: retries, countdowns, beat schedules -->
<!-- for: python -->

## Stack

| Background jobs | Celery (tasks in `tasks.py` modules, broker Redis or RabbitMQ, `celery beat` for schedules) | Mature async and scheduled work for Python services |

## Project layout

```
src/<app>/celery_app.py        the Celery app, broker and result backend from settings, autodiscover
src/<app>/<feature>/tasks.py   tasks of a feature; each one is a thin wrapper over a service function
```

## Conventions

- Workers and `celery beat` run as separate processes; the web app only calls `.delay()` / `.apply_async()`.
- Task arguments are ids and plain JSON values (`serializer="json"`), never model instances or secrets.
- Every task is idempotent; use `autoretry_for`, `retry_backoff=True`, `max_retries` and `acks_late=True` for work that must not be lost.
- Set `task_time_limit` and `task_soft_time_limit`; no task runs unbounded.
- Schedules live in code (`beat_schedule`), one entry per periodic task, with a timezone set explicitly.
- Results are not stored unless something reads them (`ignore_result=True` by default).

## Commands

| Worker | `celery -A <app>.celery_app worker -l info` |
| Scheduler | `celery -A <app>.celery_app beat -l info` |

## Testing

- Service functions are tested directly; task wiring is tested with `task_always_eager=True` or by calling `.run()`.

## Rules for agents

- Never pickle: keep the JSON serializer and `accept_content=["json"]`.
- Never call a task synchronously inside a request to "wait for it"; model it as a status the client polls.
- Never put secrets or personal data in task arguments or in the broker URL logged anywhere.
