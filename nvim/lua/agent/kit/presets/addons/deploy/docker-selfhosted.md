<!-- name: Docker, self-hosted -->
<!-- desc: Docker Compose on your own server: Caddy for TLS, healthchecks, backups, one command to update -->
<!-- for: server backend fullstack selfhosted web !mobile -->
<!-- default: backend selfhosted fullstack -->

## Stack

| Deploy | Docker Compose on a single Linux server, Caddy 2 in front (automatic HTTPS) | One machine you own, no platform lock-in, reproducible |

## Project layout

```
deploy/
  compose.yaml                 app + database + Caddy; named volumes; healthchecks; restart: unless-stopped
  Caddyfile                    domain → app:PORT, compression, security headers
  .env.example                 every variable the app reads, no real values
Dockerfile                     multi-stage: build stage, then a minimal non-root runtime image
.dockerignore
```

## Conventions

- The image is built once per commit and tagged with the git SHA; the server only pulls and restarts (`docker compose pull && docker compose up -d`).
- Configuration comes from environment variables (`deploy/.env` on the server, never committed); the app validates them at startup and exits on a missing one.
- Every container has a `healthcheck` and `restart: unless-stopped`; the app exposes `GET /healthz` (process alive) and `GET /readyz` (dependencies reachable).
- Data lives in named volumes; a nightly job dumps the database to off-site storage (restic or rclone) and a restore is tested once a month.

## Commands

| Deploy | `docker compose -f deploy/compose.yaml up -d --build` |
| Logs | `docker compose -f deploy/compose.yaml logs -f app` |

## Quality gates

- `docker build` succeeds in CI and the image runs as a non-root user; `hadolint Dockerfile` is clean.

## Rules for agents

- Never bake secrets into the image or the compose file: they come from `deploy/.env`, which is git-ignored.
- Keep the runtime image minimal (distroless, alpine or scratch) and running as a non-root user.
- A new environment variable is added to `deploy/.env.example` and to the startup validation in the same change.
- Never publish the database port on the host; only Caddy exposes 80/443.
