#!/bin/sh
# All the config's tests at once: agent and commits (scripts/test-agent.sh), Go helpers (scripts/test-go.sh),
# installer (scripts/test-install.sh), flat design (scripts/test-flat.sh), settings panel (scripts/test-prefs.sh), file operations (scripts/test-files.sh), copy diagnostics (scripts/test-diagcopy.sh), undo / clipboard / yank history (scripts/test-history.sh), code search (scripts/test-search.sh), project tasks (scripts/test-tasks.sh), .gitignore helper (scripts/test-gitignore.sh), Go project setup (scripts/test-gosetup.sh), Flutter / Dart helpers (scripts/test-flutter.sh), project documents kit (scripts/test-kit.sh), the real config loading cleanly (scripts/test-startup.sh), up-to-date cheatsheet (scripts/gen-cheatsheet.sh --check) and up-to-date web docs (scripts/gen-docs.sh --check). No network or tokens.
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
run "settings panel" "$ROOT/scripts/test-prefs.sh"
run "file operations" "$ROOT/scripts/test-files.sh"
run "copy diagnostics" "$ROOT/scripts/test-diagcopy.sh"
run "editing history" "$ROOT/scripts/test-history.sh"
run "code search" "$ROOT/scripts/test-search.sh"
run "project tasks" "$ROOT/scripts/test-tasks.sh"
run ".gitignore helper" "$ROOT/scripts/test-gitignore.sh"
run "Go project setup" "$ROOT/scripts/test-gosetup.sh"
run "Flutter / Dart helpers" "$ROOT/scripts/test-flutter.sh"
run "project documents kit" "$ROOT/scripts/test-kit.sh"
run "config loads cleanly" "$ROOT/scripts/test-startup.sh"
run "cheatsheet up to date" "$ROOT/scripts/gen-cheatsheet.sh" --check
run "web docs up to date" "$ROOT/scripts/gen-docs.sh" --check
exit "$status"
