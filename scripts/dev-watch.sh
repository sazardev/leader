#!/usr/bin/env bash
# The real-time loop for working on the desktop app (make dev). Runs Leader, then watches the sources:
#   a change in app/ (Rust) -> rebuild, and restart the window when the build works (an error is shown, the old window
#                              keeps running until the next change fixes it)
#   a change in nvim/ (Lua) -> restart the window (no build; the editor starts in ~0.2 s and restores your session)
# Polling, no extra tools: it looks at modification times twice a second. Ctrl+C stops it and closes the window.
#
#   scripts/dev-watch.sh [PROFILE] [-- leader args…]       PROFILE: fast (default), dev, release
#   LEADER_BIN=path   run that program instead of building (used by the tests of this script)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${1:-fast}"
shift || true
[ "${1:-}" = "--" ] && shift
ARGS=("$@")
case "$PROFILE" in
  dev) PDIR=debug; CARGO=(cargo build) ;;
  release) PDIR=release; CARGO=(cargo build --release) ;;
  *) PDIR="$PROFILE"; CARGO=(cargo build --profile "$PROFILE") ;;
esac
BIN="${LEADER_BIN:-$ROOT/app/target/$PDIR/leader}"
C="" N=""
if [ -t 1 ]; then C=$'\033[36m' N=$'\033[0m'; fi
say() { printf '%s[dev]%s %s\n' "$C" "$N" "$*"; }

PID=""
stop() {
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$PID" 2>/dev/null || break; sleep 0.1; done
    kill -9 "$PID" 2>/dev/null
  fi
  PID=""
}
trap 'stop; exit 0' INT TERM
trap stop EXIT

start() {
  (cd "$ROOT" && exec "$BIN" "${ARGS[@]}") &
  PID=$!
  say "running (pid $PID)"
}

build() {
  [ -n "${LEADER_BIN:-}" ] && return 0
  say "building ($PROFILE)…"
  local t0=$SECONDS out code
  out="$(cd "$ROOT/app" && "${CARGO[@]}" -p leader-gui --color always 2>&1)"
  code=$?
  # only what needs reading: warnings and errors, not the list of crates compiled
  printf '%s\n' "$out" | grep -vE '^\s*(Compiling|Fresh|Downloaded|Blocking|Finished)\b|linker stderr|linker_messages|^\s*\|?\s*$' || true
  if [ "$code" = 0 ]; then
    say "built in $((SECONDS - t0))s"
    return 0
  fi
  say "the build failed: fix it and save; the running window is left as it was"
  return 1
}

# the newest modification time among the watched files, as one number each: Rust+assets, Lua
rust_stamp() { find "$ROOT/app/crates" "$ROOT/app/assets" "$ROOT/app/Cargo.toml" -type f \( -name '*.rs' -o -name 'Cargo.toml' -o -name '*.rgba' -o -name '*.svg' \) -printf '%T@\n' 2>/dev/null | sort -n | tail -1; }
lua_stamp() { find "$ROOT/nvim" -type f \( -name '*.lua' -o -name '*.json' \) -not -path '*/node_modules/*' -printf '%T@\n' 2>/dev/null | sort -n | tail -1; }

build || true
start
rs="$(rust_stamp)"
lu="$(lua_stamp)"
say "watching app/ (rebuild + restart) and nvim/ (restart). Ctrl+C to stop."
while true; do
  sleep 0.5
  nrs="$(rust_stamp)"
  nlu="$(lua_stamp)"
  if [ "$nrs" != "$rs" ]; then
    sleep 0.4 # let an editor finish writing
    rs="$(rust_stamp)"
    lu="$(lua_stamp)"
    if build; then
      stop
      start
    fi
  elif [ "$nlu" != "$lu" ]; then
    sleep 0.3
    lu="$(lua_stamp)"
    say "Lua changed: restarting"
    stop
    start
  elif [ -n "$PID" ] && ! kill -0 "$PID" 2>/dev/null; then
    say "the window closed: waiting for a change (Ctrl+C to leave)"
    PID=""
  fi
done
