<!-- name: Redis -->
<!-- desc: an in-memory store for cache, rate limits and short-lived sessions -->
<!-- for: all -->

## Stack

| Cache | Redis 7 (`REDIS_URL`, `redis-cli` for debugging) | Cache, rate limits and sessions that must survive restarts |

## Project layout

```
compose.yaml                   `redis` service with a named volume and a healthcheck
```

## Conventions

- The URL only from `REDIS_URL`; one client per process, sized explicitly.
- Keys are namespaced (`<app>:cache:<id>`), with a TTL on every key that is not a session.
- Cache is a copy, never the source of truth: a miss recomputes from the database.

## Commands

| Cache up | `docker compose up -d redis` |
| Shell | `redis-cli -u "$REDIS_URL"` |

## Testing

- Tests use a real Redis container or a throwaway database number, never a fake in-memory store.
- Each test starts from a known state (`FLUSHDB` in setup).

## Rules for agents

- Never store the only copy of a value in Redis.
- Always set a TTL on cached data.
- Never run destructive commands (`FLUSHALL`) against a production `REDIS_URL`.
