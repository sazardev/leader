#!/usr/bin/env bash
# Leader for the desktop: the guided installer of the release package (leader-linux-x86_64.tar.gz).
# It installs the app (the `leader` binary, its menu entry and icon), makes sure the editor it runs is there (Neovim
# and Leader's config, through Leader's own installer when they are missing or old) and opens it: the first launch
# shows the welcome screen, which checks the rest and installs what is missing.
#
#   ./install.sh                 install (asks before installing the config or opening Leader; in a pipe it just does it)
#   ./install.sh --yes           ask nothing
#   ./install.sh --no-config     only the app (you manage Neovim and the config yourself)
#   ./install.sh --prefix DIR    install somewhere else than ~/.local
#   ./install.sh --uninstall     remove the app (the config and your files stay)
#   ./install.sh --dry-run       show what it would do
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="$(cat "$HERE/VERSION" 2>/dev/null || echo dev)"
REPO="https://github.com/sazardev/leader"
CONFIG_INSTALLER="https://raw.githubusercontent.com/sazardev/leader/master/install.sh"
PREFIX="$HOME/.local" YES=0 CONFIG=1 DRY=0 UNINSTALL=0
[ -t 0 ] || YES=1
while [ $# -gt 0 ]; do
  case "$1" in
    -y | --yes) YES=1 ;;
    --no-config) CONFIG=0 ;;
    --prefix) PREFIX="${2:?--prefix needs a directory}"; shift ;;
    --prefix=*) PREFIX="${1#--prefix=}" ;;
    --uninstall) UNINSTALL=1 ;;
    --dry-run) DRY=1 ;;
    -h | --help) awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); print } else exit }' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "install.sh: unknown option $1 (use --help)" >&2; exit 2 ;;
  esac
  shift
done

if [ -t 1 ]; then B=$'\033[1m' D=$'\033[2m' G=$'\033[32m' Y=$'\033[33m' R=$'\033[31m' C=$'\033[36m' N=$'\033[0m'; else B="" D="" G="" Y="" R="" C="" N=""; fi
STEP=0
step() { STEP=$((STEP + 1)); printf '\n%s%s %s%s\n' "$B" "$STEP." "$*" "$N"; }
ok() { printf '   %s✔%s %s\n' "$G" "$N" "$*"; }
info() { printf '   %s·%s %s\n' "$C" "$N" "$*"; }
warn() { printf '   %s!%s %s\n' "$Y" "$N" "$*"; }
die() { printf '   %s✘ %s%s\n' "$R" "$*" "$N" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
run() { if [ "$DRY" = 1 ]; then printf '   %s[dry-run]%s %s\n' "$D" "$N" "$*"; else "$@"; fi; }
ask() { # ask "question" → yes by default; --yes or no terminal: yes without asking
  [ "$YES" = 1 ] && return 0
  local a
  read -r -p "   $1 [Y/n] " a </dev/tty || return 0
  case "$a" in "" | y | Y | yes) return 0 ;; *) return 1 ;; esac
}
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

BIN="$PREFIX/bin/leader"
DESKTOP="$PREFIX/share/applications/leader.desktop"
ICON="$PREFIX/share/icons/hicolor/scalable/apps/leader.svg"
refresh_menus() {
  have update-desktop-database && run update-desktop-database -q "$PREFIX/share/applications" 2>/dev/null || true
  have gtk-update-icon-cache && run gtk-update-icon-cache -q -t "$PREFIX/share/icons/hicolor" 2>/dev/null || true
}

printf '\n%s  ▌ Leader %s%s  %sthe editor, in its own window%s\n' "$B" "$VERSION" "$N" "$D" "$N"

if [ "$UNINSTALL" = 1 ]; then
  step "Removing the app"
  run rm -f "$BIN" "$DESKTOP" "$ICON"
  refresh_menus
  ok "removed $BIN, its menu entry and its icon (the config in ~/.config/nvim and your files stay)"
  exit 0
fi

# ── 1. This machine ──────────────────────────────────────────────────────────
step "Checking this machine"
[ "$(uname -s)" = Linux ] || die "this package is for Linux (on macOS or Windows use Leader in a terminal: $REPO)"
[ "$(uname -m)" = x86_64 ] || die "this package is for x86_64; build it for $(uname -m) with app/install.sh from $REPO"
glibc="$(ldd --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+$' || echo 0)"
if version_ge "$glibc" 2.31; then ok "Linux x86_64, glibc $glibc"; else die "glibc $glibc is too old (2.31 or newer: Ubuntu 20.04, Debian 11, Fedora 32…)"; fi
WSL=0
[ -r /proc/version ] && grep -qi microsoft /proc/version && WSL=1
if [ "$WSL" = 1 ]; then
  if [ -e /mnt/wslg/runtime-dir/wayland-0 ]; then ok "WSL with WSLg: Leader opens on Windows and draws with your GPU"; else warn "WSL without WSLg: update WSL (wsl --update) so Linux apps get a window"; fi
elif [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
  ok "a desktop session ($([ -n "${WAYLAND_DISPLAY:-}" ] && echo Wayland || echo X11))"
else
  warn "no desktop session found here: it installs anyway, open Leader from your desktop's menu"
fi

# ── 2. The app ───────────────────────────────────────────────────────────────
step "Installing the app"
run install -Dm755 "$HERE/bin/leader" "$BIN"
run install -Dm644 "$HERE/share/icons/hicolor/scalable/apps/leader.svg" "$ICON"
if [ "$DRY" = 1 ]; then
  info "[dry-run] write $DESKTOP"
else
  mkdir -p "$(dirname "$DESKTOP")"
  sed "s|@BIN@|$BIN|" "$HERE/share/applications/leader.desktop" >"$DESKTOP"
fi
refresh_menus
if [ "$DRY" = 1 ] || "$BIN" --version >/dev/null 2>&1; then ok "$BIN"; else die "$BIN does not run here: build it from source with app/install.sh ($REPO)"; fi
ok "Leader in your applications menu"
case ":$PATH:" in *":$PREFIX/bin:"*) ;; *) warn "add $PREFIX/bin to your PATH to type \`leader\` in a shell" ;; esac

# ── 3. The editor it runs: Neovim and Leader's config ─────────────────────────
step "The editor: Neovim and Leader's config"
config="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
nvim_ok=0
if have nvim && version_ge "$(nvim --version | sed -n '1s/[^0-9]*\([0-9.]*\).*/\1/p')" 0.11; then
  nvim_ok=1
  ok "Neovim $(nvim --version | sed -n '1s/NVIM v//p')"
else
  warn "Neovim 0.11 or newer is not installed"
fi
state="missing"
if [ -f "$config/lua/core/settings.lua" ] && [ -d "$config/lua/gui" ]; then
  state="current"
  ok "Leader's config in $config"
elif [ -f "$config/lua/core/settings.lua" ] && grep -q "Leader\|leader" "$config/lua/core/settings.lua" 2>/dev/null; then
  state="old"
  warn "Leader's config is there but older than the app (no desktop support yet)"
elif [ -e "$config" ]; then
  state="other"
  warn "$config holds another Neovim config"
else
  warn "no Neovim config yet"
fi
if [ "$CONFIG" = 0 ]; then
  info "--no-config: leaving Neovim and the config as they are"
elif [ "$state" = current ] && [ "$nvim_ok" = 1 ]; then
  info "nothing to do"
else
  case "$state" in
    old) what="update Leader's config" ;;
    other) what="install Leader's config (yours is moved to nvim.bak-<date>, never deleted)" ;;
    *) what="install Neovim and Leader's config" ;;
  esac
  info "Leader's installer does it in one go: dependencies, Neovim, the config, plugins, language tools, parsers"
  if ask "$(echo "${what:0:1}" | tr '[:lower:]' '[:upper:]')${what:1}?"; then
    have curl || die "curl is needed to fetch Leader's installer"
    if [ "$DRY" = 1 ]; then
      info "[dry-run] curl -fsSL $CONFIG_INSTALLER | bash -s -- --yes"
    else
      curl -fsSL "$CONFIG_INSTALLER" | bash -s -- --yes
    fi
    ok "the editor is ready"
  else
    warn "skipped: Leader needs it to open (run this installer again, or: curl -fsSL $CONFIG_INSTALLER | bash)"
  fi
fi

# ── 4. Ready ─────────────────────────────────────────────────────────────────
step "Ready"
printf '   Open %sLeader%s from your applications menu, or type %sleader%s (any nvim argument works: leader file.go).\n' "$B" "$N" "$B" "$N"
printf '   The first launch shows the %swelcome screen%s: it checks the install and fixes what is missing with Enter.\n' "$B" "$N"
printf '   %sF10%s the menu · %sCtrl+Shift+P%s the command palette · %sCtrl+Shift+O%s your projects · %sSpace%s every editor menu\n' "$B" "$N" "$B" "$N" "$B" "$N" "$B" "$N"
case "$HERE" in
  /tmp/* | "${TMPDIR:-/tmp}"/*) undo="curl -fsSL $REPO/releases/latest/download/leader-installer.sh | bash -s -- --uninstall" ;;
  *) undo="$HERE/install.sh --uninstall" ;;
esac
printf '   %sWhat is new: %s/releases/tag/v%s · uninstall: %s%s\n' "$D" "$REPO" "$VERSION" "$undo" "$N"
if [ "$DRY" = 0 ] && [ -t 0 ] && [ -t 1 ] && { [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] || [ "$WSL" = 1 ]; } && ask "Open Leader now?"; then
  (cd "$HOME" && setsid "$BIN" >/dev/null 2>&1 &)
  ok "opening Leader"
fi
