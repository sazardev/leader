#!/bin/sh
# Tests of the language packs (Python, TypeScript/JavaScript, Rust, SQL, Swift, Make): the registry and its packs, tests in
# the editor (langtest adapters: tests from real buffers, commands, reports of real runner output), the SQL runner's
# pure parts, every project setup preset, the menus' pure helpers (scripts/test-langs.lua). No runner, database or network.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/hermetic.sh"
command -v nvim >/dev/null 2>&1 || { echo "test-langs: nvim is not in PATH" >&2; exit 2; }
state="$(mktemp -d)"
out="$(XDG_STATE_HOME="$state" AGENT_TEST_ROOT="$ROOT" NVIM_NO_LOCAL=1 NVIM_LIGHT=0 nvim -u NONE --headless -c "luafile $ROOT/scripts/test-langs.lua" 2>&1 | tr '\r' '\n')"
rm -rf "$state"
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q '^FAIL\|^ERROR\|FAILURES\|^E5' && exit 1
printf '%s\n' "$out" | grep -q 'ALL OK' || exit 1
exit 0
