#!/usr/bin/env bash
# After a release is published: points both PKGBUILDs at it (pkgver, checksums) and regenerates their .SRCINFO.
#   packaging/arch/update.sh [VERSION]     (default: the repository's VERSION)
# Then submit to the AUR (git clone ssh://aur@aur.archlinux.org/leader-editor-bin.git, copy PKGBUILD + .SRCINFO, push).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${1:-$(cat "$HERE/../../VERSION")}"
command -v makepkg >/dev/null 2>&1 || { echo "update: makepkg is needed (an Arch system)" >&2; exit 1; }
base="https://github.com/sazardev/leader"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
echo "update: $VERSION"
curl -fsSL "$base/releases/download/v$VERSION/leader-linux-x86_64.tar.gz" -o "$tmp/bin.tgz"
curl -fsSL "$base/archive/refs/tags/v$VERSION.tar.gz" -o "$tmp/src.tgz"
bin_sum="$(sha256sum "$tmp/bin.tgz" | cut -d' ' -f1)"
src_sum="$(sha256sum "$tmp/src.tgz" | cut -d' ' -f1)"
for pkg in leader-editor-bin leader-editor; do
  f="$HERE/$pkg/PKGBUILD"
  sed -i "s/^pkgver=.*/pkgver=$VERSION/; s/^pkgrel=.*/pkgrel=1/" "$f"
done
sed -i "s/^sha256sums=.*/sha256sums=('$bin_sum' 'SKIP')/" "$HERE/leader-editor-bin/PKGBUILD"
sed -i "s/^sha256sums=.*/sha256sums=('$src_sum')/" "$HERE/leader-editor/PKGBUILD"
for pkg in leader-editor-bin leader-editor; do
  (cd "$HERE/$pkg" && makepkg --printsrcinfo >.SRCINFO)
done
echo "update: PKGBUILDs and .SRCINFO written for $VERSION"
