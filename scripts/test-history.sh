#!/bin/sh
# Editing history tests (nvim/lua/history). Hermetic: no plugins,
# no config, a throwaway state directory (the real one is never touched).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v nvim >/dev/null 2>&1 || { echo "test-history: nvim is not in PATH" >&2; exit 2; }
state="$(mktemp -d)"
out="$(XDG_STATE_HOME="$state" NVIM_NO_LOCAL=1 AGENT_TEST_ROOT="$ROOT" nvim -u NONE --headless -c "luafile $ROOT/scripts/test-history.lua" 2>&1 | tr '\r' '\n')"
rm -rf "$state"
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q '^FAIL\|^ERROR\|FAILURES\|^E5' && exit 1
printf '%s\n' "$out" | grep -q 'ALL OK' || exit 1
exit 0
