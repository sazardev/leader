#!/bin/sh
# Pruebas del completado de Go propio (utils/goimpl.lua): métodos que faltan para cumplir una interfaz.
# Hermético: módulos Go temporales, sin gopls ni red. Sale con código != 0 si algo falla.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

command -v nvim >/dev/null 2>&1 || { echo "test-go: nvim no está en el PATH" >&2; exit 2; }

status=0
for suite in test-go-impl.lua; do
  out="$(NVIM_NO_LOCAL=1 NVIM_LIGHT=0 nvim --headless \
    -c "lua vim.defer_fn(function() local ok, e = pcall(dofile, '$ROOT/scripts/$suite'); if not ok then print('ERROR: ' .. tostring(e)); vim.cmd('cquit 1') end end, 800)" 2>&1 | tr '\r' '\n')"
  printf '%s\n' "$out"
  printf '%s\n' "$out" | grep -q '^FAIL\|^ERROR\|FALLOS' && status=1
  printf '%s\n' "$out" | grep -q 'TODO OK' || status=1
done
exit "$status"
