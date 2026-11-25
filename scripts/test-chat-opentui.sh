#!/bin/sh
# Optional OpenTUI chat bridge: same runtime, atomic snapshot/command files and scoped stop.
set -e
cd "$(dirname "$0")/.."
. scripts/hermetic.sh
AGENT_TEST_ROOT="$PWD" NVIM_NO_LOCAL=1 NVIM_LIGHT=1 nvim --headless -c "luafile scripts/test-chat-opentui.lua" -c "qa!" 2>&1 | tee /tmp/chat-opentui.out
tail -n 1 /tmp/chat-opentui.out | grep -q " 0 failed"
