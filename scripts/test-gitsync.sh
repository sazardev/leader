#!/bin/sh
# Tests of the git sync actions (nvim/lua/gitsync, <leader>GP push, <leader>Gu pull, <leader>GF fetch): the exact
# commands, the guards, and a real push/pull/fetch against a local bare repository. Hermetic: no network or credentials.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/hermetic.sh"
command -v nvim >/dev/null 2>&1 || { echo "test-gitsync: nvim is not in PATH" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "test-gitsync: git is not in PATH" >&2; exit 2; }
state="$(mktemp -d)"
out="$(XDG_STATE_HOME="$state" AGENT_TEST_ROOT="$ROOT" NVIM_NO_LOCAL=1 NVIM_LIGHT=0 nvim -u NONE --headless -c "luafile $ROOT/scripts/test-gitsync.lua" 2>&1 | tr '\r' '\n')"
rm -rf "$state"
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q '^FAIL\|^ERROR\|FAILURES\|^E5' && exit 1
printf '%s\n' "$out" | grep -q 'ALL OK' || exit 1
exit 0
