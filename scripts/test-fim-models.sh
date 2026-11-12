#!/bin/sh
# FIM model catalog and hardware detection (nvim/lua/fim/{models,hardware}.lua): pure parsers, the recommendation by
# VRAM, what the picker offers and how the current model matches. Hermetic: no plugins, no config, no network.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/hermetic.sh"
command -v nvim >/dev/null 2>&1 || { echo "test-fim-models: nvim is not in PATH" >&2; exit 2; }
state="$(mktemp -d)"
out="$(XDG_STATE_HOME="$state" NVIM_NO_LOCAL=1 AGENT_TEST_ROOT="$ROOT" nvim -u NONE --headless -c "luafile $ROOT/scripts/test-fim-models.lua" -c "qa!" 2>&1 | tr '\r' '\n')"
rm -rf "$state"
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q '^FAIL\|^ERROR\|FAILURES\|^E5' && exit 1
printf '%s\n' "$out" | grep -q 'ALL OK' || exit 1
exit 0
