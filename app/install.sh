#!/usr/bin/env bash
# Installs the Leader desktop app: builds `leader` (Rust, release, pinned Cargo.lock) and puts it on the desktop
# (application menu entry + icon). Linux and WSL (WSLg). The editor itself is Neovim with this repo's config, so run the
# main ./install.sh first (or ./install.sh --app, which ends here).
#
#   app/install.sh              build and install into ~/.local (bin/leader, share/applications, share/icons)
#   --prefix DIR                install somewhere else (default ~/.local)
#   --uninstall                 remove what this script installed
#   --dry-run                   show what it would do
#
# Rust is installed with rustup (no sudo, ~/.cargo) when cargo is missing. No -dev packages are needed: windowing and
# GPU libraries (Wayland/X11, Vulkan/GL) are loaded at runtime, the ones every desktop already has.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="$HOME/.local" DRY=0 UNINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --prefix) PREFIX="${2:?--prefix needs a directory}"; shift ;;
    --prefix=*) PREFIX="${1#--prefix=}" ;;
    --uninstall) UNINSTALL=1 ;;
    --dry-run) DRY=1 ;;
    -h | --help) awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); print } else exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "app/install.sh: unknown argument: $1 (use --help)" >&2; exit 2 ;;
  esac
  shift
done

if [ -t 1 ]; then B=$'\033[1m' G=$'\033[32m' Y=$'\033[33m' R=$'\033[31m' N=$'\033[0m'; else B="" G="" Y="" R="" N=""; fi
ok() { printf '  %s✔%s %s\n' "$G" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; }
die() { printf '  %s✘ %s%s\n' "$R" "$*" "$N" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
run() { if [ "$DRY" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else "$@"; fi; }

BIN="$PREFIX/bin/leader"
printf '\n%s==>%s Leader desktop app\n' "$B" "$N"
[ "$(uname -s)" = Linux ] || die "the desktop app is Linux-only for now (macOS/Windows: use Leader in a terminal)"

if [ "$UNINSTALL" = 1 ]; then
  exec bash "$ROOT/package/install.sh" --uninstall --prefix "$PREFIX"
fi

# ── Rust ─────────────────────────────────────────────────────────────────────
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
if ! have cargo; then
  warn "cargo not found: installing Rust with rustup (into ~/.cargo, no sudo)"
  have curl || die "curl is required to install Rust (https://rustup.rs)"
  if [ "$DRY" = 1 ]; then
    printf '  [dry-run] curl https://sh.rustup.rs | sh -s -- -y --profile minimal\n'
  else
    curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --no-modify-path >/dev/null
    . "$HOME/.cargo/env"
  fi
fi
if have cargo; then ok "$(cargo --version)"; fi
have nvim || warn "nvim is not in PATH: the app runs Neovim, install it first (./install.sh)"

# ── Build ────────────────────────────────────────────────────────────────────
printf '  building (release; the first build takes a minute or two)…\n'
T0=$SECONDS
run cargo build --release --locked --manifest-path "$ROOT/Cargo.toml" -p leader-gui
ok "built in $((SECONDS - T0))s"

# ── Install ──────────────────────────────────────────────────────────────────
# the same files and the same installer as the release package: stage them like it, then run its install.sh
VERSION="$(cat "$ROOT/../VERSION")"
if [ "$DRY" = 1 ]; then
  printf '  [dry-run] stage the files and run package/install.sh --no-config --prefix %s\n' "$PREFIX"
else
  stage="$(mktemp -d)"
  trap 'rm -rf "$stage"' EXIT
  pkg="$stage/leader-$VERSION-local"
  mkdir -p "$pkg"
  bash "$ROOT/package/stage-tree.sh" "$ROOT/target/release/leader" "$pkg" "$VERSION"
  install -m755 "$ROOT/package/install.sh" "$pkg/install.sh"
  echo "$VERSION" >"$pkg/VERSION"
  LEADER_LOCAL_BUILD=1 bash "$pkg/install.sh" --yes --no-config --prefix "$PREFIX"
fi
