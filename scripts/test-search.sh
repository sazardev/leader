#!/bin/sh
# Tests for the code search (nvim/lua/codesearch): ranking and the treesitter index. Needs the real config (parsers and
# textobjects queries) and ripgrep. No network or tokens.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v nvim >/dev/null 2>&1 || { echo "test-search: nvim is not in PATH" >&2; exit 2; }
command -v rg >/dev/null 2>&1 || { echo "test-search: rg is not in PATH" >&2; exit 2; }
out="$(AGENT_TEST_ROOT="$ROOT" NVIM_NO_LOCAL=1 NVIM_LIGHT=0 nvim --headless \
  -c "lua vim.defer_fn(function() local ok, e = pcall(dofile, '$ROOT/scripts/test-search.lua'); if not ok then print('ERROR: ' .. tostring(e)); vim.cmd('cquit 1') end end, 1200)" 2>&1 | tr '\r' '\n')"
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q '^FAIL\|^ERROR\|FAILURES' && exit 1
printf '%s\n' "$out" | grep -q 'ALL OK' || exit 1
exit 0
