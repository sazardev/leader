#!/bin/sh
# Todas las pruebas de la config de una vez: agente y commits (scripts/test-agent.sh), ayudas de Go (scripts/test-go.sh),
# instalador (scripts/test-install.sh) y cheatsheet al día (scripts/gen-cheatsheet.sh --check). Sin red ni tokens.
# Cada suite sigue pudiéndose correr sola. Sale con código != 0 si alguna falla.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

status=0
run() {
  name="$1"; shift
  if "$@" >/tmp/nvim-config-test.log 2>&1; then
    printf '  ✔ %s\n' "$name"
  else
    printf '  ✘ %s  (detalle: %s)\n' "$name" "$*" >&2
    sed -n '1,40p' /tmp/nvim-config-test.log | grep -E '^FAIL|^ERROR|FALLOS' | head -10 >&2
    status=1
  fi
}

run "agente y commits" "$ROOT/scripts/test-agent.sh"
run "ayudas de Go" "$ROOT/scripts/test-go.sh"
run "instalador" "$ROOT/scripts/test-install.sh"
run "cheatsheet al día" "$ROOT/scripts/gen-cheatsheet.sh" --check
exit "$status"
