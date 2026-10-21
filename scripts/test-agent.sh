#!/bin/sh
# Tests for the inline agent (lua/agent): protocol, backend parsers, diff, target, local backends and setup;
# and for the commit panel (lua/commit).
# No network or tokens (the Ollama/OpenAI servers are fake: scripts/fake-llm.py). Requires nvim and the linked config.
# Exits with a code != 0 if anything fails.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/hermetic.sh"

command -v nvim >/dev/null 2>&1 || { echo "test-agent: nvim is not in PATH" >&2; exit 2; }

status=0
for suite in test-agent.lua test-agent-backends.lua test-commit.lua test-fix.lua test-agent-tests.lua test-agent-history.lua test-agent-flow.lua test-agent-batch.lua test-agent-review.lua test-agent-plan.lua test-agent-cache.lua test-agent-docs.lua test-agent-next.lua test-agent-keys.lua test-agent-convert.lua test-agent-types.lua test-agent-dart.lua test-agent-calls.lua test-agent-conflict.lua test-agent-doctor.lua test-agent-doctor-known.lua; do
  out="$(AGENT_TEST_ROOT="$ROOT" NVIM_NO_LOCAL=1 NVIM_LIGHT=0 nvim --headless \
    -c "lua vim.defer_fn(function() local ok, e = pcall(dofile, '$ROOT/scripts/$suite'); if not ok then print('ERROR: ' .. tostring(e)); vim.cmd('cquit 1') end end, 1200)" 2>&1 | tr '\r' '\n')"
  printf '%s\n' "$out"
  printf '%s\n' "$out" | grep -q '^FAIL\|^ERROR\|FAILURES' && status=1
  printf '%s\n' "$out" | grep -q 'ALL OK' || status=1
done
exit "$status"
