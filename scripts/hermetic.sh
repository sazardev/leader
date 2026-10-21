#!/bin/sh
# Sourced by the test scripts: every Neovim they start gets its own, throwaway state directory (sessions, recent files, agent
# history, shada, logs). Without it a test that opens temp files in the repo writes them into YOUR state: it once replaced
# the repo's real session with files that no longer exist and left ~1400 sessions of /tmp folders behind.
# One directory per run (the outermost script makes it, the ones it calls share it), removed when that script ends.
if [ -z "${LEADER_TEST_STATE:-}" ]; then
  LEADER_TEST_STATE="$(mktemp -d)"
  export LEADER_TEST_STATE
  trap 'rm -rf "$LEADER_TEST_STATE"' EXIT
fi
export XDG_STATE_HOME="$LEADER_TEST_STATE"
