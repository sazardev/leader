#!/usr/bin/env bash
# Leader for the desktop, in one command: downloads the latest release package, checks its SHA-256 and runs its guided
# installer (app/package/install.sh). Options go to that installer:
#
#   curl -fsSL https://github.com/sazardev/leader/releases/latest/download/leader-installer.sh | bash
#   curl -fsSL https://github.com/sazardev/leader/releases/latest/download/leader-installer.sh | bash -s -- --no-config
set -euo pipefail

BASE="${LEADER_RELEASE_URL:-https://github.com/sazardev/leader/releases/latest/download}"
PKG="leader-linux-x86_64.tar.gz"
command -v curl >/dev/null 2>&1 || { echo "leader: curl is required" >&2; exit 1; }
[ "$(uname -s)-$(uname -m)" = Linux-x86_64 ] || { echo "leader: the package is for Linux x86_64 (this is $(uname -s) $(uname -m))" >&2; exit 1; }

dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
echo "leader: downloading $PKG…"
curl -fsSL "$BASE/$PKG" -o "$dir/$PKG"
curl -fsSL "$BASE/$PKG.sha256" -o "$dir/$PKG.sha256"
(cd "$dir" && sha256sum -c --quiet "$PKG.sha256") || { echo "leader: the download does not match its checksum" >&2; exit 1; }
tar -xzf "$dir/$PKG" -C "$dir"
bash "$dir"/leader-*-linux-x86_64/install.sh "$@"
