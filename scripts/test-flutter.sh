#!/bin/sh
# Tests of the Flutter / Dart helpers (nvim/lua/dartgen): build_runner's output in both formats, generated parts, and
# the codegen watch against a fake `dart` (statusline, diagnostics, notes, light mode). Hermetic: no Flutter SDK,
# network or tokens.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v nvim >/dev/null 2>&1 || { echo "test-flutter: nvim is not in PATH" >&2; exit 2; }
out="$(AGENT_TEST_ROOT="$ROOT" NVIM_NO_LOCAL=1 NVIM_LIGHT=0 nvim -u NONE --headless -c "luafile $ROOT/scripts/test-flutter.lua" 2>&1 | tr '\r' '\n')"
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -q '^FAIL\|^ERROR\|FAILURES\|^E5' && exit 1
printf '%s\n' "$out" | grep -q 'ALL OK' || exit 1
exit 0
