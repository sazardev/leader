#!/usr/bin/env bash
# Leader's speed benchmark: what the user waits for, measured the same way every time.
#   scripts/bench.sh [--runs N] [--app PATH] [--app-only] [--json]
# App: time from launch to each startup phase (LEADER_TIMING marks), the first frame and the first frame with the real
# content (`content_frame`), median and best of N.
# Editor: Neovim's own startup, opening a big file, and the file list a picker would show. Nothing leaves the machine.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNS=9
APP="$ROOT/app/target/release/leader"
JSON=0
APP_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --runs) RUNS="$2"; shift 2 ;;
    --app) APP="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    --app-only) APP_ONLY=1; shift ;;
    *) echo "usage: bench.sh [--runs N] [--app PATH] [--app-only] [--json]" >&2; exit 2 ;;
  esac
done
command -v nvim >/dev/null 2>&1 || { echo "bench: nvim is not in PATH" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "bench: python3 is needed for the statistics" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

now_ms() { python3 -c 'import time; print(time.perf_counter()*1000)'; }

# one number per line in, "median best worst" out
stats() { python3 -c '
import sys, statistics
v = sorted(float(x) for x in sys.stdin.read().split())
print("%.1f %.1f %.1f" % (statistics.median(v), v[0], v[-1])) if v else print("- - -")'; }

rows=()
row() { # name, unit values file
  read -r med best worst < <(stats < "$2")
  rows+=("$1|$med|$best|$worst")
}

# ── the app ────────────────────────────────────────────────────────────────
if [ -x "$APP" ]; then
  for i in $(seq "$RUNS"); do
    # BENCH_ENV="LEADER_NO_HOLD=1 LEADER_NO_WARM=1" runs a variant of the same binary (the switches are bench-only)
    # shellcheck disable=SC2086
    env ${BENCH_ENV:-} LEADER_TIMING=1 LEADER_SNAPSHOT="$tmp/s.png" LEADER_SNAPSHOT_MS=300 timeout 30 "$APP" -n "$ROOT" 2>&1 \
      | grep -E '^\[leader\] +[0-9.]+ ms  ' | while read -r _ ms _ what; do
          key="$(printf '%s' "$what" | sed -E 's/:.*//; s/ /_/g')"
          echo "$ms" >> "$tmp/app.$key"
        done
  done
  # content_frame: the first frame drawn after the config said its first screen was complete = the real editor on screen
  for f in nvim_spawned_and_attached nvim_spawned window_created fonts_ready attached first_flush gpu_ready first_frame content_frame; do
    [ -f "$tmp/app.$f" ] && row "app: $f" "$tmp/app.$f"
  done
  [ -f "$tmp/app.first_frame" ] || echo "bench: the app printed no timings (no display?)" >&2
else
  echo "bench: app skipped (no binary at $APP; build it with make build PROFILE=release)" >&2
fi

if [ "$APP_ONLY" = 0 ]; then
# ── Neovim ─────────────────────────────────────────────────────────────────
for i in $(seq "$RUNS"); do
  nvim --headless --startuptime "$tmp/st.log" +qa >/dev/null 2>&1
  awk '/NVIM STARTED/ { print $1 }' "$tmp/st.log" >> "$tmp/nvim.start"
done
row "nvim: startup (headless, to quit)" "$tmp/nvim.start"

# a big file: 60k lines of Lua (1 MB, still treated as code), a huge one (4 MB, the big-file guard), and plain text
python3 - "$tmp" <<'PY'
import sys
d = sys.argv[1]
with open(d + "/big.lua", "w") as f:
    for i in range(20000):
        f.write(f"local function f{i}(a, b)\n  return a + b * {i}\nend\n")
with open(d + "/huge.lua", "w") as f:
    for i in range(80000):
        f.write(f"local function f{i}(a, b)\n  return a + b * {i}\nend\n")
with open(d + "/big.txt", "w") as f:
    for i in range(200000):
        f.write(f"line {i} " + "x" * 60 + "\n")
PY
for kind in lua huge.lua txt; do
  for i in $(seq "$RUNS"); do
    t0=$(now_ms)
    nvim --headless "$tmp/$([ "$kind" = huge.lua ] && echo huge.lua || echo big.$kind)" +qa >/dev/null 2>&1
    t1=$(now_ms)
    python3 -c "print($t1 - $t0)" >> "$tmp/open.$kind"
  done
  row "nvim: open $([ "$kind" = huge.lua ] && echo huge.lua || echo big.$kind) and quit" "$tmp/open.$kind"
done

# the first picker of a session (Telescope's modules are preloaded when idle) and the code search index: built from
# nothing in the first session, loaded from the state dir in the next ones
for i in $(seq "$RUNS"); do
  nvim --headless -c "luafile $ROOT/scripts/bench-picker.lua" 2>/dev/null | tr '\r' '\n' | sed -n 's/^picker_ms=//p' >> "$tmp/picker"
done
[ -s "$tmp/picker" ] && row "picker: first find_files, results shown" "$tmp/picker"
# an empty state dir for the code search, so the first run builds the index and the next ones load it
search_state="$tmp/search-state"
for i in 1 2 3; do
  out="$(cd "$ROOT" && XDG_STATE_HOME="$search_state" nvim --headless -c "luafile $ROOT/scripts/bench-search.lua" 2>/dev/null | tr '\r' '\n' | sed -n 's/^search_ms=\([0-9]*\) .*/\1/p')"
  [ "$i" = 1 ] && echo "$out" > "$tmp/search.first" || echo "$out" >> "$tmp/search.later"
done
[ -s "$tmp/search.first" ] && row "search: index, first session (builds it)" "$tmp/search.first"
[ -s "$tmp/search.later" ] && row "search: index, later sessions (stored)" "$tmp/search.later"

# the file list a picker shows, on this repo
for i in $(seq "$RUNS"); do
  t0=$(now_ms)
  if command -v fd >/dev/null 2>&1; then fd -t f . "$ROOT" >/dev/null 2>&1
  elif command -v rg >/dev/null 2>&1; then rg --files "$ROOT" >/dev/null 2>&1
  else git -C "$ROOT" ls-files >/dev/null 2>&1; fi
  t1=$(now_ms)
  python3 -c "print($t1 - $t0)" >> "$tmp/files"
done
row "files: list this repo" "$tmp/files"

fi

# ── report ─────────────────────────────────────────────────────────────────
if [ "$JSON" = 1 ]; then
  printf '{'
  sep=""
  for r in "${rows[@]}"; do IFS='|' read -r n m b w <<<"$r"; printf '%s"%s":{"median":%s,"best":%s,"worst":%s}' "$sep" "$n" "$m" "$b" "$w"; sep=","; done
  printf '}\n'
else
  printf '\n  %-36s %9s %9s %9s   (ms, %s runs)\n' "" median best worst "$RUNS"
  for r in "${rows[@]}"; do IFS='|' read -r n m b w <<<"$r"; printf '  %-36s %9s %9s %9s\n' "$n" "$m" "$b" "$w"; done
  echo
fi
