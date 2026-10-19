<!-- name: Cron / systemd timers -->
<!-- desc: scheduled scripts with cron or systemd timers and lock files; no queue and no extra service -->
<!-- for: server backend selfhosted cli-desktop data-ai !mobile -->

## Stack

| Background jobs | Plain scheduled commands (systemd timers or cron) running one-shot CLI entry points | Zero moving parts for periodic work on a single host |

## Project layout

```
cmd/ or scripts/jobs/          one executable entry point per job, each exits 0 on success and non-zero on failure
deploy/systemd/                <job>.service and <job>.timer units (or deploy/crontab)
```

## Conventions

- A job is a normal CLI command that does one thing and exits; the same command runs by hand, in tests and in the timer.
- Prefer systemd timers (`OnCalendar=`, `Persistent=true`, `RandomizedDelaySec=`) over cron; with cron, set `MAILTO` or log to a file and use absolute paths.
- Prevent overlap with `flock -n /run/<job>.lock <command>` (or a unit that cannot start twice).
- Every job is idempotent and safe to run again after a missed or failed run.
- Output goes to stdout/stderr (journald); failures are visible with `systemctl status` and an alert on non-zero exit.
- Timezone is explicit (UTC unless the business rule says otherwise).

## Commands

| Timers | `systemctl list-timers` |
| Job logs | `journalctl -u <job>.service -n 100` |

## Rules for agents

- Never schedule work with `sleep` loops or in-process timers inside the web server.
- Never write jobs that assume they run exactly once; design for repeats and gaps.
- Never put secrets in the crontab or unit files; use `EnvironmentFile=` with restricted permissions.
