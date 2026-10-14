#!/bin/sh
# All the config's tests at once: agent and commits (scripts/test-agent.sh), Go helpers (scripts/test-go.sh),
# installer (scripts/test-install.sh), flat design (scripts/test-flat.sh) and up-to-date cheatsheet (scripts/gen-cheatsheet.sh --check). No network or tokens.
# Each suite can still be run on its own. Exits with a code != 0 if any fails.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

status=0
run() {
  name="$1"; shift
  if "$@" >/tmp/nvim-config-test.log 2>&1; then
    printf '  ✔ %s\n' "$name"
  else
    printf '  ✘ %s  (details: %s)\n' "$name" "$*" >&2
    sed -n '1,40p' /tmp/nvim-config-test.log | grep -E '^FAIL|^ERROR|FAILURES' | head -10 >&2
    status=1
  fi
}

run "agent and commits" "$ROOT/scripts/test-agent.sh"
run "Go helpers" "$ROOT/scripts/test-go.sh"
run "installer" "$ROOT/scripts/test-install.sh"
run "flat design" "$ROOT/scripts/test-flat.sh"
run "cheatsheet up to date" "$ROOT/scripts/gen-cheatsheet.sh" --check
exit "$status"
