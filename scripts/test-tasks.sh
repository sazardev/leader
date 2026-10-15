#!/bin/sh
# Tests of the project tasks (nvim/lua/tasks): provider parsers on canned output, Make against a real make, finding sources,
# the cache, running and "run last". Hermetic: temp projects and a throwaway state directory. No network or tokens.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v nvim >/dev/null 2>&1 || { echo "test-tasks: nvim is not in PATH" >&2; exit 2; }
state="$(mktemp -d)"
out="$(XDG_STATE_HOME="$state" AGENT_TEST_ROOT="$ROOT" NVIM_NO_LOCAL=1 NVIM_LIGHT=0 nvim -u NONE --headless -c "luafile $ROOT/scripts/test-tasks.lua" 2>&1 | tr '\r' '\n')"
rm -rf "$state"
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q '^FAIL\|^ERROR\|FAILURES\|^E5' && exit 1
printf '%s\n' "$out" | grep -q 'ALL OK' || exit 1
exit 0
