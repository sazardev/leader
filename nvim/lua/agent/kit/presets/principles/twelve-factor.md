<!-- name: Twelve-Factor app -->
<!-- desc: config in the environment, stateless processes, backing services, logs as streams, dev/prod parity -->

### Twelve-Factor app

- **One codebase**, many deploys; environments differ only by configuration.
- **Explicit dependencies**: declared and pinned in the manifest and lockfile; nothing relies on system-wide packages.
- **Config in the environment**: URLs, credentials and feature flags come from env vars, validated at startup; no per-environment code branches.
- **Backing services** (databases, caches, queues, mail) are attached resources addressed by URL and swappable without code changes.
- **Build, release, run** are separate stages; a release is immutable and identified (version, commit).
- **Stateless processes**: no local session state or files that must survive a restart; state lives in backing services.
- **Disposability**: fast startup, graceful shutdown on SIGTERM (finish in-flight work, close connections), safe to kill at any time.
- **Logs are event streams** to stdout/stderr; the platform collects and routes them, the app never manages log files.
- **Dev/prod parity**: same backing service types and versions locally (containers), short time between write and deploy.
- Review check: no hardcoded environment values, no writes to local disk that matter, graceful shutdown still works.
