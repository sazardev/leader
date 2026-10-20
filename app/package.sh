#!/usr/bin/env bash
# Builds the Linux release of the desktop app and everything that goes with it, in app/dist/:
#
#   leader-linux-x86_64.tar.gz (+ .sha256)   the guided-install package (install.sh inside; what leader-installer.sh fetches)
#   leader-editor_VERSION_amd64.deb          Debian, Ubuntu, Mint, Pop!_OS… (dpkg -i / apt install ./file.deb);
#                                            leader-editor-amd64.deb is the same file under a name without the version
#   leader-installer.sh                      the one-command bootstrap (checks the checksum and the signature)
#   SHA256SUMS                               every file above
#   *.asc                                    detached signatures (the release key, see packaging/README.md)
#   leader-releases.asc                      the public key
#
# The binary runs on glibc 2.31 and newer (Ubuntu 20.04, Debian 11, Fedora 32…): built with cargo-zigbuild, everything
# else it needs is loaded at runtime. The Arch packages are PKGBUILDs (packaging/arch/), built from these files.
# Needs cargo, zig, cargo-zigbuild, ar, xz, rsvg-convert is only for assets/make-icons.sh. Signing needs the key
# "Leader Releases" in $GNUPGHOME (default ~/.gnupg-leader-releases); without it the files are built unsigned.
#
#   ./package.sh            build, and sign when the key is there
#   ./package.sh --no-sign  build only
set -euo pipefail

APP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$APP")"
VERSION="$(cat "$ROOT/VERSION")"
NAME="leader-$VERSION-linux-x86_64"
TARGET="x86_64-unknown-linux-gnu.2.31"
DIST="$APP/dist"
APP_ID="io.github.sazardev.Leader"
SIGN=1
[ "${1:-}" = "--no-sign" ] && SIGN=0

command -v cargo-zigbuild >/dev/null 2>&1 || { echo "package: cargo-zigbuild is missing (cargo install cargo-zigbuild)" >&2; exit 1; }
command -v zig >/dev/null 2>&1 || { echo "package: zig is missing (https://ziglang.org/download)" >&2; exit 1; }
command -v ar >/dev/null 2>&1 || { echo "package: ar (binutils) is missing" >&2; exit 1; }

echo "package: building leader $VERSION for glibc 2.31+"
cargo zigbuild --release --locked --manifest-path "$APP/Cargo.toml" --target "$TARGET" -p leader-gui
BIN="$APP/target/x86_64-unknown-linux-gnu/release/leader"
[ "$("$BIN" --version)" = "leader $VERSION" ] || { echo "package: the binary says $("$BIN" --version), expected $VERSION" >&2; exit 1; }

rm -rf "$DIST"
STAGE="$DIST/$NAME"
mkdir -p "$STAGE"

# ── tarball ─────────────────────────────────────────────────────────────────
"$APP/package/stage-tree.sh" "$BIN" "$STAGE" "$VERSION"
install -m755 "$APP/package/install.sh" "$STAGE/install.sh"
echo "$VERSION" >"$STAGE/VERSION"
cp "$ROOT/LICENSE" "$STAGE/LICENSE"
awk -v v="## [$VERSION]" 'index($0, v) == 1 { on = 1; print; next } on && /^## \[/ { exit } on' "$ROOT/CHANGELOG.md" >"$STAGE/CHANGELOG.md"
cat >"$STAGE/README.md" <<EOF
# Leader $VERSION for the desktop

The Leader editor (Neovim with Leader's config) in its own GPU window: Zed-like menus, a command palette, your projects,
full mouse, and the whole of Leader inside. Linux x86_64 with glibc 2.31 or newer, Wayland or X11 (and WSL with WSLg).

    ./install.sh            # guided: the app, then Neovim and Leader's config if they are missing, then it opens
    ./install.sh --help     # options (--yes, --no-config, --prefix, --uninstall)

The first launch shows the welcome screen: it checks the install and fixes what is missing with Enter.
What is new: CHANGELOG.md. More: https://sazardev.github.io/leader/
Verify a download: packaging/README.md in the repository (SHA256SUMS and signatures).
EOF
tar --owner=0 --group=0 --numeric-owner -C "$DIST" -czf "$DIST/leader-linux-x86_64.tar.gz" "$NAME"
(cd "$DIST" && sha256sum leader-linux-x86_64.tar.gz >leader-linux-x86_64.tar.gz.sha256)

# ── .deb (built by hand: ar + two tarballs; no dpkg-deb needed) ─────────────────────────────────────────────────
DEB="leader-editor_${VERSION}_amd64.deb"
DEBDIR="$DIST/deb"
mkdir -p "$DEBDIR/root/usr" "$DEBDIR/control"
"$APP/package/stage-tree.sh" "$BIN" "$DEBDIR/root/usr" "$VERSION"
SIZE="$(du -sk "$DEBDIR/root" | cut -f1)"
cat >"$DEBDIR/control/control" <<EOF
Package: leader-editor
Version: $VERSION
Section: editors
Priority: optional
Architecture: amd64
Installed-Size: $SIZE
Depends: libc6 (>= 2.31), git, curl
Recommends: neovim (>= 0.11), ripgrep, fd-find, libwayland-client0, libxkbcommon0, libvulkan1 | libegl1
Suggests: nodejs, golang-go
Maintainer: sazardev <sazardev@users.noreply.github.com>
Homepage: https://sazardev.github.io/leader/
Description: Neovim with a fast, opinionated config in its own GPU window
 Leader is Neovim for working: a small config that starts in about 20 ms, in a
 native window drawn with your GPU. Zed-like menus, a command palette, your
 projects with their sessions, an inline AI agent, and every key you know.
 .
 The first launch without a Neovim config runs leader-setup, which installs
 Leader's config for your user. Needs Neovim 0.11 or newer (a newer one than
 some releases ship: leader-setup installs it when it is missing).
EOF
(cd "$DEBDIR/root" && find . -type f -exec md5sum {} + | sed 's| \./| |' | sort -k2) >"$DEBDIR/control/md5sums"
tar --owner=0 --group=0 --numeric-owner -C "$DEBDIR/control" -cJf "$DEBDIR/control.tar.xz" .
tar --owner=0 --group=0 --numeric-owner -C "$DEBDIR/root" -cJf "$DEBDIR/data.tar.xz" .
printf '2.0\n' >"$DEBDIR/debian-binary"
(cd "$DEBDIR" && ar rc "$DIST/$DEB" debian-binary control.tar.xz data.tar.xz)
rm -rf "$DEBDIR"

# ── installer, checksums, signatures ─────────────────────────────────────────
# a name without the version, so documentation can link to .../releases/latest/download/leader-editor-amd64.deb
cp "$DIST/$DEB" "$DIST/leader-editor-amd64.deb"
install -m755 "$APP/package/leader-installer.sh" "$DIST/leader-installer.sh"
cp "$ROOT/packaging/leader-releases.asc" "$DIST/leader-releases.asc"
rm -rf "$STAGE"
(cd "$DIST" && sha256sum leader-linux-x86_64.tar.gz "$DEB" leader-editor-amd64.deb leader-installer.sh >SHA256SUMS)

if [ "$SIGN" = 1 ]; then
  export GNUPGHOME="${GNUPGHOME:-$HOME/.gnupg-leader-releases}"
  if gpg --list-secret-keys "Leader Releases" >/dev/null 2>&1; then
    for f in leader-linux-x86_64.tar.gz "$DEB" leader-editor-amd64.deb leader-installer.sh SHA256SUMS; do
      gpg --batch --yes --armor --detach-sign --local-user "Leader Releases" --output "$DIST/$f.asc" "$DIST/$f"
    done
    echo "package: signed with $(gpg --list-keys --with-colons "Leader Releases" | awk -F: '/^fpr/ { print $10; exit }')"
  else
    echo "package: the signing key \"Leader Releases\" is not in $GNUPGHOME: files left unsigned" >&2
  fi
fi
ls -la "$DIST"
