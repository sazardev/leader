#!/bin/sh
# Tests of the release kit (nvim/lua/release, <leader>GR): changelog from Conventional Commits and the next version,
# the release checklist, the PR request, and the flows on a temp git repository. Hermetic: no network or tokens.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v nvim >/dev/null 2>&1 || { echo "test-release: nvim is not in PATH" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "test-release: git is not in PATH" >&2; exit 2; }
state="$(mktemp -d)"
out="$(XDG_STATE_HOME="$state" AGENT_TEST_ROOT="$ROOT" NVIM_NO_LOCAL=1 NVIM_LIGHT=0 nvim -u NONE --headless -c "luafile $ROOT/scripts/test-release.lua" 2>&1 | tr '\r' '\n')"
rm -rf "$state"
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q '^FAIL\|^ERROR\|FAILURES\|^E5' && exit 1
printf '%s\n' "$out" | grep -q 'ALL OK' || exit 1
exit 0
