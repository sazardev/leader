<!-- name: Docker Compose stack -->
<!-- desc: self-hosted multi-service app: app + Postgres + Valkey + Caddy, restic backups, healthchecks, updates -->

# STACK.md: Docker Compose stack

## Summary

A self-hosted application made of several services on one Linux server, described by one `compose.yaml`: the app
container (any language), PostgreSQL, Valkey (Redis-compatible) for cache and queues, Caddy for HTTPS, a scheduled
restic backup job, and optionally Uptime Kuma for monitoring. Everything is reproducible from the repository plus a
`.env` file; updating is pull + up; restoring is a documented, tested command.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Orchestration | Docker Engine + Compose v2 (`compose.yaml`) | One file describes the whole system |
| App | One image built from the repo (multi-stage, non-root) | Language-agnostic; versioned by git SHA |
| Database | PostgreSQL 16 (official image) | Mature, transactional |
| Cache / queue | Valkey 8 (Redis-compatible, BSD license) | Sessions, cache, job queues |
| Reverse proxy | Caddy 2 | Automatic HTTPS, HTTP/3, simple config |
| Backups | restic to S3-compatible storage (scheduled container or systemd timer) + `pg_dump` | Encrypted, deduplicated, verifiable |
| Monitoring | Uptime Kuma (optional) + container healthchecks | Alerts when something is down |
| Logs | Docker `json-file` with rotation (`max-size`, `max-file`) | Disk never fills up |
| Secrets | `.env` on the server (git-ignored), Docker secrets for the DB password | Nothing secret in git |
| Testing | `docker compose config` + a CI smoke test that boots the stack and hits `/healthz` | The file is tested too |
| Lint | `hadolint` for Dockerfiles, `docker compose config -q` | Catches mistakes before deploy |
| Deploy | SSH + `docker compose pull && docker compose up -d` (or a pull-based updater) | No platform required |

## Project layout

```
compose.yaml                  all services: app, db, valkey, caddy, backup (+ kuma profile)
compose.override.yaml         local development: ports, bind mounts, no TLS (not used on the server)
.env.example                  every variable, documented, no real values
Caddyfile                     {$DOMAIN} → app:8080, headers, compression
app/
  Dockerfile                  multi-stage, non-root, HEALTHCHECK
  ...                         the application's own code
backup/
  backup.sh                   pg_dump → restic backup → restic forget --prune (retention policy)
  restore.sh                  restic restore → psql restore → app restart
docs/operations.md            install, update, rollback, restore, rotate secrets
```

Each service has one responsibility; the app talks to `db` and `valkey` by service name on an internal network.

## Conventions

- Images are pinned by tag (and digest for third-party images); `latest` is never used.
- Every service has a `healthcheck`, `restart: unless-stopped` and log rotation; `depends_on` uses `condition: service_healthy`.
- Only Caddy publishes ports (80/443); `db` and `valkey` live on an internal network with no published ports.
- Persistent data only in named volumes (`db-data`, `valkey-data`, `caddy-data`); the app container is stateless.
- Migrations run as a one-shot service (`app migrate`) before the app starts, never by hand on the server.
- Backups run nightly; retention: 7 daily, 4 weekly, 6 monthly; a restore drill is done monthly and recorded in `docs/operations.md`.
- Update = `git pull && docker compose pull && docker compose up -d`; rollback = previous image tag in `.env`.

## Commands

| Task | Command |
| --- | --- |
| Start (dev) | `docker compose up -d --build` |
| Start (server) | `docker compose -f compose.yaml up -d` |
| Logs | `docker compose logs -f app` |
| Validate | `docker compose config -q` |
| Update | `docker compose pull && docker compose up -d` |
| Backup now | `docker compose run --rm backup /backup/backup.sh` |
| Restore | `docker compose run --rm backup /backup/restore.sh <snapshot>` |
| Lint | `hadolint app/Dockerfile` |

## Testing

- The app's own tests run in its language toolchain.
- CI boots the full stack with `docker compose up -d --wait` and checks `/healthz`, then tears it down.
- `backup.sh` and `restore.sh` are tested in CI against a throwaway stack: backup, wipe, restore, compare row counts.

## Quality gates

- `docker compose config -q` and `hadolint` clean; images build in CI.
- The smoke test and the backup/restore test pass before a release tag.

## Dependencies

- Official images for Postgres, Valkey, Caddy, restic; anything else needs a reason and a maintainer check.
- Do NOT use: `latest` tags, bind-mounting host directories for database data, publishing database ports, Watchtower-style blind auto-updates of databases, Kubernetes for a single server.

## Rules for agents

- Never commit `.env` or any secret; add new variables to `.env.example` with a comment.
- Never publish `db` or `valkey` ports on the host.
- Every new service gets a healthcheck, restart policy, log rotation and a pinned image.
- Persistent data only in named volumes, and every new volume is added to the backup script.
- Never run migrations manually on the server; add them to the migrate one-shot service.
- Changes to `compose.yaml` must pass `docker compose config -q` and the CI smoke test.
- Document any operational change (ports, volumes, new secrets, update steps) in `docs/operations.md` in the same change.
- Keep the app image stateless and non-root.
