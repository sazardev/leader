#!/bin/sh
# Pruebas del instalador: los ajustes por máquina (scripts/install-local.lua) y el modo --dry-run de install.sh.
# Hermético: no instala nada, no toca nvim/lua/local.lua. Sale con código != 0 si algo falla.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

command -v nvim >/dev/null 2>&1 || { echo "test-install: nvim no está en el PATH" >&2; exit 2; }

out="$(AGENT_TEST_ROOT="$ROOT" nvim -u NONE --headless \
  -c "lua local ok, e = pcall(dofile, '$ROOT/scripts/test-install-local.lua'); if not ok then print('ERROR: ' .. tostring(e)); vim.cmd('cquit 1') end" 2>&1 | tr '\r' '\n')"
printf '%s\n' "$out"
status=0
printf '%s\n' "$out" | grep -q '^FAIL\|^ERROR\|FALLOS' && status=1
printf '%s\n' "$out" | grep -q 'TODO OK' || status=1

# install.sh: sintaxis y opciones desconocidas
bash -n "$ROOT/install.sh" || status=1
"$ROOT/install.sh" --bogus >/dev/null 2>&1 && { echo "FAIL install.sh acepta una opción desconocida"; status=1; }
"$ROOT/install.sh" --help | grep -q -- '--agent' || { echo "FAIL --help no documenta --agent"; status=1; }
exit "$status"
