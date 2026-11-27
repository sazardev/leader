#!/bin/sh
# Tests for the Python project helpers (utils/python.lua): module paths, pyproject scripts, versions, the venv and the
# entry points (scripts, __main__.py, Django, FastAPI, Flask, Streamlit, plain scripts). Hermetic: temporary project
# directories, no uv, pytest or network. Exits with a code != 0 if anything fails.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/hermetic.sh"

command -v nvim >/dev/null 2>&1 || { echo "test-python: nvim is not in PATH" >&2; exit 2; }

out="$(NVIM_NO_LOCAL=1 NVIM_LIGHT=0 nvim --headless \
  -c "lua vim.defer_fn(function() local ok, e = pcall(dofile, '$ROOT/scripts/test-python.lua'); if not ok then print('ERROR: ' .. tostring(e)); vim.cmd('cquit 1') end end, 800)" 2>&1 | tr '\r' '\n')"
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q '^FAIL\|^ERROR\|FAILURES' && exit 1
printf '%s\n' "$out" | grep -q 'ALL OK' || exit 1

# The pretty runner (<leader>pr): the pure helpers and the real command, without uv or network
if command -v python3 >/dev/null 2>&1; then
  python3 "$ROOT/scripts/test-pypretty.py" || exit 1
else
  echo "test-python: python3 is not in PATH (the pretty runner was not tested)"
fi
exit 0
