<!-- name: Coolify (self-hosted PaaS) -->
<!-- desc: push-to-deploy on your own server with Coolify: builds, TLS, databases and backups from one panel -->
<!-- for: server backend fullstack selfhosted web !mobile -->

## Stack

| Deploy | Coolify on your own server (Dockerfile or Nixpacks build, automatic TLS via its proxy) | Heroku-like push-to-deploy, but on a machine you own |

## Conventions

- The app builds from the repository's `Dockerfile` (preferred over auto-detection, so local and server builds match).
- Environment variables and secrets are set in Coolify, never committed; `.env.example` lists them all.
- Databases created in Coolify have scheduled backups to S3-compatible storage enabled.
- Deploys are triggered by pushes to `main` (webhook); a failing healthcheck keeps the previous container running.

## Commands

| Deploy | `git push origin main` (Coolify builds and rolls out) |

## Rules for agents

- Never commit secrets or a real `.env`; add new variables to `.env.example`.
- Keep `GET /healthz` fast and dependency-free: Coolify uses it to decide whether the new version goes live.
