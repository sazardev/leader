#!/bin/sh
# A swap file left by an editor that died is removed when the file is opened again; a swap owned by a live
# process is kept. Uses the real config in a throwaway state (scripts/hermetic.sh) and no local overrides.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/hermetic.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SWAP="$XDG_STATE_HOME/nvim/swap"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Leave a swap behind the way a crash does: start nvim, then SIGKILL it.
stale_swap() {
  file="$1"
  printf 'hola\n' >"$file"
  nvim --headless -u NONE "$file" +"sleep 30" >/dev/null 2>&1 &
  pid=$!
  sleep 1
  kill -9 "$pid" 2>/dev/null || true
  sleep 0.3
  find "$SWAP" -name "*$(basename "$file").swp" 2>/dev/null | head -1
}

# ── stale: opening the file removes the swap and edits it ───────────────────
file="$TMP/stale.txt"
swap="$(stale_swap "$file")"
[ -n "$swap" ] || fail "could not create a stale swap file"
NVIM_NO_LOCAL=1 nvim --headless "$file" "+lua print('opened')" +qa >/dev/null 2>&1 ||
  fail "opening the file with a stale swap failed"
[ -e "$swap" ] && fail "the stale swap file was not removed"
echo "ok   stale swap removed"

# ── live: another nvim still owns the file, so its swap stays ───────────────
file="$TMP/live.txt"
printf 'hola\n' >"$file"
nvim --headless -u NONE "$file" +"sleep 30" >/dev/null 2>&1 &
pid=$!
sleep 1
swap="$(find "$SWAP" -name "*$(basename "$file").swp" 2>/dev/null | head -1)"
[ -n "$swap" ] || fail "could not create the live swap file"
NVIM_NO_LOCAL=1 nvim --headless "$file" "+lua print('opened')" +qa >/dev/null 2>&1 ||
  fail "opening the file with a live swap failed"
[ -e "$swap" ] || fail "the live swap file was removed"
kill "$pid" 2>/dev/null || true
echo "ok   live swap kept"

echo "ALL OK"
