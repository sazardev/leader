<!-- name: Static binary + systemd -->
<!-- desc: one static binary on a Linux server, a hardened systemd unit, Caddy in front for TLS -->
<!-- for: go rust !mobile -->

## Stack

| Deploy | One static binary copied to a Linux server, run by a hardened systemd unit, Caddy 2 in front | No container runtime, minimal moving parts, instant restarts |

## Project layout

```
deploy/
  app.service                  systemd unit: DynamicUser, ProtectSystem=strict, Restart=on-failure, EnvironmentFile
  Caddyfile                    domain → localhost:PORT, automatic HTTPS
  install.sh                   copy binary, reload unit, health check
```

## Conventions

- The binary embeds its static assets and migrations; the release is one file plus the unit.
- Configuration from `/etc/<app>/env` (EnvironmentFile, mode 0600), validated at startup.
- The unit runs without root (`DynamicUser=yes`) with `ProtectSystem=strict`, `NoNewPrivileges=yes`, and writes only to `StateDirectory`.
- Logs go to stdout and are read with `journalctl -u <app>`.

## Commands

| Deploy | `scp bin/app server:/usr/local/bin/app && ssh server 'sudo systemctl restart app'` |
| Logs | `journalctl -u app -f` |

## Rules for agents

- Never require root at runtime; anything that needs a privilege goes in the unit, not the code.
- Builds are static (`CGO_ENABLED=0` for Go, a musl target for Rust) unless a C dependency is unavoidable and documented.
