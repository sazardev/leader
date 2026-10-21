#!/bin/sh
# Installer tests: the per-machine settings (scripts/install-local.lua) and install.sh's --dry-run mode.
# Hermetic: installs nothing, does not touch nvim/lua/local.lua. Exits with a code != 0 if anything fails.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/hermetic.sh"

command -v nvim >/dev/null 2>&1 || { echo "test-install: nvim is not in PATH" >&2; exit 2; }

out="$(AGENT_TEST_ROOT="$ROOT" nvim -u NONE --headless \
  -c "lua local ok, e = pcall(dofile, '$ROOT/scripts/test-install-local.lua'); if not ok then print('ERROR: ' .. tostring(e)); vim.cmd('cquit 1') end" 2>&1 | tr '\r' '\n')"
printf '%s\n' "$out"
status=0
printf '%s\n' "$out" | grep -q '^FAIL\|^ERROR\|FAILURES' && status=1
printf '%s\n' "$out" | grep -q 'ALL OK' || status=1

# install.sh: syntax and unknown options
bash -n "$ROOT/install.sh" || status=1
"$ROOT/install.sh" --bogus >/dev/null 2>&1 && { echo "FAIL install.sh accepts an unknown option"; status=1; }
"$ROOT/install.sh" --help | grep -q -- '--agent' || { echo "FAIL --help does not document --agent"; status=1; }
"$ROOT/install.sh" --help | grep -q -- '--ask' || { echo "FAIL --help does not document --ask"; status=1; }
# one command: piped (curl | bash) there is no repo next to the script, so it must bootstrap; --dry-run only prints the plan
plan="$(cat "$ROOT/install.sh" | NVIM_CONFIG_DIR=/nonexistent/my-nvim bash -s -- --dry-run --lang go 2>&1)"
printf '%s\n' "$plan" | grep -q 'would fetch .* into /nonexistent/my-nvim' || { echo "FAIL piped install.sh does not bootstrap: $plan"; status=1; }
printf '%s\n' "$plan" | grep -q -- '--lang go' || { echo "FAIL the bootstrap does not forward its options"; status=1; }
# from a clone it must NOT bootstrap (no "would fetch")
"$ROOT/install.sh" --dry-run --no-deps --no-plugins 2>&1 | grep -q 'would fetch' && { echo "FAIL install.sh bootstraps from inside a clone"; status=1; }
exit "$status"
