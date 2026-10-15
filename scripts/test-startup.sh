#!/bin/sh
# Smoke test of the real config (scripts/test-startup.lua): a normal start plus one file of each language must raise no
# error (statusline components, plugin specs, ftplugins). Requires nvim and the installed plugins; no network.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v nvim >/dev/null 2>&1 || { echo "test-startup: nvim is not in PATH" >&2; exit 2; }
state="$(mktemp -d)"
out="$(XDG_STATE_HOME="$state" NVIM_NO_LOCAL=1 NVIM_LIGHT=1 timeout 120 nvim --headless -c "luafile $ROOT/scripts/test-startup.lua" 2>&1 | tr '\r' '\n')"
code=$?
rm -rf "$state"
printf '%s\n' "$out" | grep -E '^(FAIL|ALL OK|FAILURES)'
printf '%s\n' "$out" | grep -q 'ALL OK' || exit 1
exit 0
