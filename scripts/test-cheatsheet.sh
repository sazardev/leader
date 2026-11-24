#!/bin/sh
# Searchable Mappings view: pure model/controls/windows, then a smoke test against the real config.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/hermetic.sh"
command -v nvim >/dev/null 2>&1 || { echo "test-cheatsheet: nvim is not in PATH" >&2; exit 2; }

out="$(AGENT_TEST_ROOT="$ROOT" timeout 30s nvim -u NONE --headless -c "luafile $ROOT/scripts/test-cheatsheet.lua" 2>&1 | tr '\r' '\n')"
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q '^FAIL\|^ERROR\|FAILURES\|^E5' && exit 1
printf '%s\n' "$out" | grep -q 'ALL OK' || exit 1

live="$(NVIM_NO_LOCAL=1 NVIM_LIGHT=0 timeout 120s nvim --headless -c "luafile $ROOT/scripts/test-cheatsheet-live.lua" 2>&1 | tr '\r' '\n')"
printf '%s\n' "$live"
printf '%s\n' "$live" | grep -q 'LIVE OK' || exit 1
exit 0
