<!-- name: Fly.io -->
<!-- desc: containers close to users on Fly Machines, fly.toml, rolling deploys, managed Postgres -->
<!-- for: server backend fullstack selfhosted !mobile -->

## Stack

| Deploy | Fly.io (Fly Machines from the `Dockerfile`, `fly.toml`) | Global regions, rolling deploys, simple scaling |

## Project layout

```
fly.toml                       app name, primary region, [http_service], health checks, [deploy] release_command
```

## Conventions

- Secrets with `fly secrets set`, never in `fly.toml`.
- Database migrations run as the `release_command` before new machines start.
- Health checks in `fly.toml` point at `GET /healthz`; `min_machines_running` is at least 1 for anything user-facing.

## Commands

| Deploy | `fly deploy` |
| Logs | `fly logs` |

## Rules for agents

- Never put secrets in `fly.toml` or the Dockerfile.
- A schema change must be backward compatible with the version still running during a rolling deploy.
