#!/bin/sh
# Tests of agent skills (nvim/lua/skills, <leader>aK): frontmatter parsing, inference
# (0-config suggestions per model/stack), discovery + CRUD on disk, matching and the
# marketplace UI. No network.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/hermetic.sh"
command -v nvim >/dev/null 2>&1 || { echo "test-skills: nvim is not in PATH" >&2; exit 2; }
state="$(mktemp -d)"
out="$(XDG_STATE_HOME="$state" AGENT_TEST_ROOT="$ROOT" NVIM_NO_LOCAL=1 NVIM_LIGHT=0 nvim -u NONE --headless -c "luafile $ROOT/scripts/test-skills.lua" 2>&1 | tr '\r' '\n')"
rm -rf "$state"
printf '%s\n' "$out"
if printf '%s\n' "$out" | grep -q '^FAIL\|^ERROR\|FAILURES\|^E5'; then
  exit 1
fi
printf '%s\n' "$out" | grep -q 'ALL OK'
