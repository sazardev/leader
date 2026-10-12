#!/bin/sh
# Regenera CHEATSHEET.md desde los keymaps reales de la config.
#   scripts/gen-cheatsheet.sh           escribe CHEATSHEET.md
#   scripts/gen-cheatsheet.sh --check   exit 1 si CHEATSHEET.md está desactualizado
# Requiere nvim y los plugins instalados (esta config enlazada como la config de nvim).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

command -v nvim >/dev/null 2>&1 || { echo "gen-cheatsheet: nvim no está en el PATH" >&2; exit 2; }

CHEATSHEET_OUT="$ROOT/CHEATSHEET.md" \
CHEATSHEET_CHECK="$([ "$1" = "--check" ] && echo 1 || echo 0)" \
NVIM_NO_LOCAL=1 NVIM_LIGHT=0 \
  nvim --headless -c "luafile $ROOT/scripts/gen-cheatsheet.lua"
