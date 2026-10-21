#!/bin/sh
# Evals of the inline agent against models (see scripts/eval.lua for the EVAL_* variables and evals/README.md).
# Runs on the user's real config and backends (it spends what the models cost, capped by EVAL_MAX_USD); the free
# regression check of the harness itself is scripts/test-agent-eval.lua (in test-agent.sh).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v nvim >/dev/null 2>&1 || { echo "eval: nvim is not in PATH" >&2; exit 2; }
tmp="$(mktemp)"
AGENT_TEST_ROOT="$ROOT" NVIM_LIGHT=0 nvim --headless \
  -c "lua vim.defer_fn(function() local ok, e = pcall(dofile, '$ROOT/scripts/eval.lua'); if not ok then io.stdout:write('ERROR: ' .. tostring(e) .. '\\n'); vim.cmd('cquit 1') end end, 1200)" >"$tmp" 2>&1
status=$?
tr '\r' '\n' <"$tmp"
rm -f "$tmp"
exit "$status"
