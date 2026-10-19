#!/bin/sh
# Tests of the project kit (nvim/lua/agent/kit, <leader>aS): presets, documents text, project snapshot, flows with a fake model
# (test-kit.lua), and the build's quality harness: answer cleaner, wiring, the use phase and its drivers (test-kit-use.lua;
# the tmux and Playwright parts are skipped when those are missing), and the build's scopes: foundation, domain, design
# or all (test-kit-scope.lua), the records and coverage (test-kit-records.lua), features and recipes
# (test-kit-feature.lua).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v nvim >/dev/null 2>&1 || { echo "test-kit: nvim is not in PATH" >&2; exit 2; }
status=0
for suite in test-kit.lua test-kit-use.lua test-kit-scope.lua test-kit-records.lua test-kit-feature.lua; do
  state="$(mktemp -d)"
  out="$(XDG_STATE_HOME="$state" AGENT_TEST_ROOT="$ROOT" NVIM_NO_LOCAL=1 NVIM_LIGHT=0 nvim -u NONE --headless -c "luafile $ROOT/scripts/$suite" 2>&1 | tr '\r' '\n')"
  rm -rf "$state"
  printf '%s\n' "$out"
  if printf '%s\n' "$out" | grep -q '^FAIL\|^ERROR\|FAILURES\|^E5' || ! printf '%s\n' "$out" | grep -q 'ALL OK'; then
    status=1
  fi
done
exit $status
