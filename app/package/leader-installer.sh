#!/usr/bin/env bash
# Leader for the desktop, in one command: downloads the latest release package, checks its SHA-256 and its signature,
# and runs its guided installer (app/package/install.sh). Options go to that installer:
#
#   curl -fsSL https://github.com/sazardev/leader/releases/latest/download/leader-installer.sh | bash
#   curl -fsSL https://github.com/sazardev/leader/releases/latest/download/leader-installer.sh | bash -s -- --no-config
#
# The release is signed with the key "Leader Releases" (fingerprint below, also in packaging/README.md). With gpg
# installed the signature MUST be valid by exactly that key; without gpg only the checksum is checked and it says so.
# LEADER_VERIFY=0 skips the signature (a mirror that does not carry it); LEADER_RELEASE_URL points at another mirror.
set -euo pipefail

BASE="${LEADER_RELEASE_URL:-https://github.com/sazardev/leader/releases/latest/download}"
PKG="leader-linux-x86_64.tar.gz"
FPR="8E437A7936E48EAEDA88CD73A7DCC3DBB671476A"
command -v curl >/dev/null 2>&1 || { echo "leader: curl is required" >&2; exit 1; }
[ "$(uname -s)-$(uname -m)" = Linux-x86_64 ] || { echo "leader: the package is for Linux x86_64 (this is $(uname -s) $(uname -m))" >&2; exit 1; }

dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
echo "leader: downloading $PKG…"
curl -fsSL "$BASE/$PKG" -o "$dir/$PKG"
curl -fsSL "$BASE/$PKG.sha256" -o "$dir/$PKG.sha256"
(cd "$dir" && sha256sum -c --quiet "$PKG.sha256") || { echo "leader: the download does not match its checksum" >&2; exit 1; }

if [ "${LEADER_VERIFY:-1}" = 0 ]; then
  echo "leader: signature check skipped (LEADER_VERIFY=0)"
elif command -v gpg >/dev/null 2>&1; then
  curl -fsSL "$BASE/$PKG.asc" -o "$dir/$PKG.asc" || { echo "leader: this release has no signature ($PKG.asc); LEADER_VERIFY=0 installs it anyway" >&2; exit 1; }
  curl -fsSL "$BASE/leader-releases.asc" -o "$dir/leader-releases.asc" || { echo "leader: the release key could not be downloaded" >&2; exit 1; }
  export GNUPGHOME="$dir/gnupg"
  mkdir -m 700 "$GNUPGHOME"
  gpg --batch --quiet --import "$dir/leader-releases.asc" 2>/dev/null
  # the downloaded key must be the one this script knows, and the signature must be by it
  have="$(gpg --batch --with-colons --list-keys 2>/dev/null | awk -F: '/^fpr/ { print $10; exit }')"
  [ "$have" = "$FPR" ] || { echo "leader: the release key is not the expected one ($have)" >&2; exit 1; }
  status="$(gpg --batch --status-fd 1 --verify "$dir/$PKG.asc" "$dir/$PKG" 2>/dev/null || true)"
  printf '%s\n' "$status" | grep -q "^\[GNUPG:\] VALIDSIG .* $FPR\$\|^\[GNUPG:\] VALIDSIG $FPR " || { echo "leader: the signature is not valid for the Leader Releases key" >&2; exit 1; }
  echo "leader: checksum and signature OK (Leader Releases ${FPR: -16})"
else
  echo "leader: gpg is not installed: only the checksum was checked (install gpg to verify the signature too)"
fi

tar -xzf "$dir/$PKG" -C "$dir"
bash "$dir"/leader-*-linux-x86_64/install.sh "$@"
