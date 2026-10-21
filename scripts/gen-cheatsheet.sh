#!/bin/sh
# Regenerates CHEATSHEET.md from the config's real keymaps.
#   scripts/gen-cheatsheet.sh           writes CHEATSHEET.md
#   scripts/gen-cheatsheet.sh --check   exit 1 if CHEATSHEET.md is out of date
# Requires nvim and the plugins installed (this config linked as the nvim config).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/hermetic.sh"

command -v nvim >/dev/null 2>&1 || { echo "gen-cheatsheet: nvim is not in PATH" >&2; exit 2; }

CHEATSHEET_OUT="$ROOT/CHEATSHEET.md" \
CHEATSHEET_CHECK="$([ "$1" = "--check" ] && echo 1 || echo 0)" \
NVIM_NO_LOCAL=1 NVIM_LIGHT=0 HERDR_ENV=1 NVIM_EXPERIMENTAL=1 \
  nvim --headless -c "luafile $ROOT/scripts/gen-cheatsheet.lua"
