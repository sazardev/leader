#!/bin/sh
# Tests for the custom Go completion (utils/go*.lua), the shared `go test` line (utils/gotest.lua), the langtest Go
# adapter (JSON events, marks, build failures) and GoHawk diagnostics (utils/gohawk.lua): missing interface methods,
# if err, mappers, wiring, enums, port, HTTP, test commands and the gohawk JSON parser. Hermetic: temporary Go
# modules, no gopls, gohawk or network. Exits with a code != 0 if anything fails.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/hermetic.sh"

command -v nvim >/dev/null 2>&1 || { echo "test-go: nvim is not in PATH" >&2; exit 2; }

status=0
for suite in test-go-impl.lua test-go-smart.lua test-gorun.lua test-gohawk.lua test-go-tests.lua; do
  out="$(NVIM_NO_LOCAL=1 NVIM_LIGHT=0 nvim --headless \
    -c "lua vim.defer_fn(function() local ok, e = pcall(dofile, '$ROOT/scripts/$suite'); if not ok then print('ERROR: ' .. tostring(e)); vim.cmd('cquit 1') end end, 800)" 2>&1 | tr '\r' '\n')"
  printf '%s\n' "$out"
  printf '%s\n' "$out" | grep -q '^FAIL\|^ERROR\|FAILURES' && status=1
  printf '%s\n' "$out" | grep -q 'ALL OK' || status=1
done
exit "$status"
