#!/bin/sh
# Tests of the desktop app (app/, the `leader` binary): its config side (nvim/lua/gui/: install checks, welcome screen,
# app bar state; scripts/test-gui.lua, needs only nvim and the installed plugins), the Rust unit tests (grid, screen
# model, input, box drawing, atlas, app bar) and the protocol against a real `nvim --embed --clean` (no window or GPU
# needed). The Rust part is skipped without cargo.
# --gui also opens the real window with the real config and checks a frame (needs a display: Wayland/X11/WSLg).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/hermetic.sh"
command -v nvim >/dev/null 2>&1 || { echo "test-app: nvim is not in PATH" >&2; exit 2; }
state="$(mktemp -d)"
out="$(XDG_STATE_HOME="$state" AGENT_TEST_ROOT="$ROOT" NVIM_NO_LOCAL=1 NVIM_LIGHT=1 timeout 300 nvim --headless -c "luafile $ROOT/scripts/test-gui.lua" 2>&1 | tr '\r' '\n')"
rm -rf "$state"
printf '%s\n' "$out" | grep -E '^(FAIL|ALL OK|FAILURES)|E5[0-9]{2}'
printf '%s\n' "$out" | grep -q 'ALL OK' || exit 1

[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
if ! command -v cargo >/dev/null 2>&1; then
  echo "test-app: Rust part SKIPPED (no cargo; the app is optional)"
  exit 0
fi

cargo test --locked -q --manifest-path "$ROOT/app/Cargo.toml" 2>&1 || exit 1

if [ "${1:-}" = --gui ]; then
  cargo build --locked -q --release --manifest-path "$ROOT/app/Cargo.toml" -p leader-gui || exit 1
  shot="$(mktemp --suffix .png)"
  XDG_STATE_HOME="$(mktemp -d)" LEADER_SNAPSHOT="$shot" LEADER_SNAPSHOT_MS=800 timeout 20 "$ROOT/app/target/release/leader" "$ROOT/app/Cargo.toml" 2>&1 |
    grep -v MESA || true
  # A real frame is a few KB at least; an empty or failed one is not written or is tiny.
  size="$(wc -c <"$shot" 2>/dev/null || echo 0)"
  rm -f "$shot"
  [ "$size" -gt 4000 ] || { echo "FAIL: no frame from the window (snapshot $size bytes)"; exit 1; }
  echo "gui frame ok ($size bytes)"
fi
echo "ALL OK"
