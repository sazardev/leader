#!/bin/sh
# Pure + rendering tests for the chat (<leader>aC): triggers, files, commands,
# history, heights, mention parsing and every shape a model can produce.
# No network, no real state (hermetic).
set -e
cd "$(dirname "$0")/.."
. scripts/hermetic.sh
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-/tmp/leader-test-xdg-chat-pure}"
mkdir -p "$XDG_CONFIG_HOME"
ln -sfn "$PWD/nvim" "$XDG_CONFIG_HOME/nvim"
AGENT_TEST_ROOT="$PWD" nvim --headless -c "luafile scripts/test-chat-pure.lua" -c "qa!" 2>&1 | tee /tmp/chat-pure.out
tail -n 1 /tmp/chat-pure.out | grep -q " 0 failed"
