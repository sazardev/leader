#!/bin/sh
# Tests of the Go project setup (nvim/lua/gosetup, <leader>gS): preset files, what they are filled with, never overwriting, the
# flows (variant picker, misnamed config, several at once) and, where the tools are installed, the presets checked by the
# tools themselves (golangci-lint v2 `config verify`, air's own default keys, lefthook validate). Hermetic: temp projects.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v nvim >/dev/null 2>&1 || { echo "test-gosetup: nvim is not in PATH" >&2; exit 2; }
state="$(mktemp -d)"
out="$(XDG_STATE_HOME="$state" AGENT_TEST_ROOT="$ROOT" NVIM_NO_LOCAL=1 NVIM_LIGHT=0 nvim -u NONE --headless -c "luafile $ROOT/scripts/test-gosetup.lua" 2>&1 | tr '\r' '\n')"
rm -rf "$state"
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q '^FAIL\|^ERROR\|FAILURES\|^E5' && exit 1
printf '%s\n' "$out" | grep -q 'ALL OK' || exit 1
exit 0
