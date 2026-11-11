#!/usr/bin/env bash
# Leader, in one command — https://leader.sazardev.stream/install
#
#   curl -fsSL https://leader.sazardev.stream/install | bash
#
# On Linux x86_64 it installs the desktop app (its own GPU window) and then Neovim and Leader's config, so the first
# launch is a fully working editor (the welcome screen installs whatever is still missing). On macOS and other
# architectures it installs the config only (the editor without the app). Options go to the installer:
#
#   curl -fsSL https://leader.sazardev.stream/install | bash -s -- --lang go
#   curl -fsSL https://leader.sazardev.stream/install | bash -s -- --no-config
#   curl -fsSL https://leader.sazardev.stream/install | bash -s -- --uninstall
#
# The release is checksummed and the desktop installer verifies it. LEADER_VERIFY=0 skips the signature (the 1.15-1.18
# assets are unsigned until the Leader Releases key is back); LEADER_RELEASE_URL / LEADER_CONFIG_URL point elsewhere.
set -euo pipefail

BASE="${LEADER_RELEASE_URL:-https://github.com/sazardev/leader/releases/latest/download}"
CONFIG="${LEADER_CONFIG_URL:-https://raw.githubusercontent.com/sazardev/leader/master/install.sh}"

command -v curl >/dev/null 2>&1 || { echo "leader: curl is required" >&2; exit 1; }

# What the app installer understands (--prefix DIR, --uninstall, --no-config, --dry-run, --yes) stays here; everything
# else is the config installer's (--lang, --theme, --light, --agent…). Both get --yes/--dry-run.
APP_ARGS=()
CONFIG_ARGS=()
UNINSTALL=0
NO_CONFIG=0
while [ $# -gt 0 ]; do
  case "$1" in
    --uninstall) UNINSTALL=1; shift ;;
    --no-config) NO_CONFIG=1; shift ;;
    --prefix) APP_ARGS+=(--prefix "${2:?--prefix needs a directory}"); shift 2 ;;
    --prefix=*) APP_ARGS+=("$1"); shift ;;
    --yes) APP_ARGS+=(--yes); CONFIG_ARGS+=(--yes); shift ;;
    --dry-run) APP_ARGS+=(--dry-run); CONFIG_ARGS+=(--dry-run); shift ;;
    *) CONFIG_ARGS+=("$1"); shift ;;
  esac
done

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64)
    dir="$(mktemp -d)"
    trap 'rm -rf "$dir"' EXIT
    echo "leader: downloading the desktop app…"
    curl -fsSL "$BASE/leader-installer.sh" -o "$dir/leader-installer.sh"
    if [ "$UNINSTALL" = 1 ]; then
      LEADER_VERIFY=0 bash "$dir/leader-installer.sh" --uninstall ${APP_ARGS[@]+"${APP_ARGS[@]}"}
      exit 0
    fi
    echo "leader: installing the desktop app…"
    LEADER_VERIFY=0 bash "$dir/leader-installer.sh" --no-config ${APP_ARGS[@]+"${APP_ARGS[@]}"}
    if [ "$NO_CONFIG" = 0 ]; then
      echo "leader: installing Neovim and Leader's config…"
      curl -fsSL "$CONFIG" | bash -s -- ${CONFIG_ARGS[@]+"${CONFIG_ARGS[@]}"}
    fi
    echo "leader: done. Open Leader from your applications menu (or run leader) — the welcome screen finishes the setup."
    ;;
  *)
    if [ "$UNINSTALL" = 1 ]; then
      echo "leader: the desktop app is Linux only; nothing to uninstall here" >&2
      exit 0
    fi
    echo "leader: installing Leader's config for Neovim ($(uname -s) $(uname -m))…"
    curl -fsSL "$CONFIG" | bash -s -- ${CONFIG_ARGS[@]+"${CONFIG_ARGS[@]}"}
    ;;
esac
