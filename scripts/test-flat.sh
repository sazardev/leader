#!/bin/sh
# Flat design tests (nvim/lua/ui/flat): tokens, highlight groups, notifier fallback. Hermetic: no plugins, no config.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v nvim >/dev/null 2>&1 || { echo "test-flat: nvim is not in PATH" >&2; exit 2; }
out="$(AGENT_TEST_ROOT="$ROOT" nvim -u NONE --headless -c "luafile $ROOT/scripts/test-flat.lua" 2>&1 | tr '\r' '\n')"
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q '^FAIL\|^ERROR\|FAILURES\|^E5' && exit 1
printf '%s\n' "$out" | grep -q 'ALL OK' || exit 1
exit 0
