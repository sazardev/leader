#!/bin/sh
# Tests of the .gitignore helper (nvim/lua/gitignore): preset files, detection, composing without duplicates, the real
# rules checked by `git check-ignore` (nothing a project needs may be ignored), the checklist modal and the whole flow.
# Hermetic: temp repos. No network or tokens.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/hermetic.sh"
command -v nvim >/dev/null 2>&1 || { echo "test-gitignore: nvim is not in PATH" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "test-gitignore: git is not in PATH" >&2; exit 2; }
state="$(mktemp -d)"
out="$(XDG_STATE_HOME="$state" AGENT_TEST_ROOT="$ROOT" NVIM_NO_LOCAL=1 NVIM_LIGHT=0 nvim -u NONE --headless -c "luafile $ROOT/scripts/test-gitignore.lua" 2>&1 | tr '\r' '\n')"
rm -rf "$state"
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q '^FAIL\|^ERROR\|FAILURES\|^E5' && exit 1
printf '%s\n' "$out" | grep -q 'ALL OK' || exit 1
exit 0
