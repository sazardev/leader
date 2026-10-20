#!/usr/bin/env bash
# Builds the Linux release package of the desktop app: a `leader` that runs on glibc 2.31 and newer (Ubuntu 20.04,
# Debian 11, Fedora 32… built with cargo-zigbuild; everything else it needs is loaded at runtime), its menu entry and
# icon, the guided installer, the version's changelog and a short README, as
#   app/dist/leader-linux-x86_64.tar.gz (+ .sha256) and app/dist/leader-installer.sh (the one-command bootstrap).
# Needs cargo, zig and cargo-zigbuild (`cargo install cargo-zigbuild`).
set -euo pipefail

APP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$APP")"
VERSION="$(cat "$ROOT/VERSION")"
NAME="leader-$VERSION-linux-x86_64"
TARGET="x86_64-unknown-linux-gnu.2.31"
DIST="$APP/dist"
STAGE="$DIST/$NAME"

command -v cargo-zigbuild >/dev/null 2>&1 || { echo "package: cargo-zigbuild is missing (cargo install cargo-zigbuild)" >&2; exit 1; }
command -v zig >/dev/null 2>&1 || { echo "package: zig is missing (https://ziglang.org/download)" >&2; exit 1; }

echo "package: building leader $VERSION for glibc 2.31+"
cargo zigbuild --release --locked --manifest-path "$APP/Cargo.toml" --target "$TARGET" -p leader-gui
BIN="$APP/target/x86_64-unknown-linux-gnu/release/leader"
[ "$("$BIN" --version)" = "leader $VERSION" ] || { echo "package: the binary says $("$BIN" --version), expected $VERSION" >&2; exit 1; }

rm -rf "$DIST"
mkdir -p "$STAGE/bin" "$STAGE/share/applications" "$STAGE/share/icons/hicolor/scalable/apps"
install -m755 "$BIN" "$STAGE/bin/leader"
install -m644 "$APP/assets/leader.desktop" "$STAGE/share/applications/leader.desktop"
install -m644 "$APP/assets/leader.svg" "$STAGE/share/icons/hicolor/scalable/apps/leader.svg"
install -m755 "$APP/package/install.sh" "$STAGE/install.sh"
echo "$VERSION" >"$STAGE/VERSION"
# this version's section of the changelog
awk -v v="## [$VERSION]" 'index($0, v) == 1 { on = 1; print; next } on && /^## \[/ { exit } on' "$ROOT/CHANGELOG.md" >"$STAGE/CHANGELOG.md"
cat >"$STAGE/README.md" <<EOF
# Leader $VERSION for the desktop

The Leader editor (Neovim with Leader's config) in its own GPU window: Zed-like menus, a command palette, your projects,
full mouse, and the whole of Leader inside. Linux x86_64 with glibc 2.31 or newer, Wayland or X11 (and WSL with WSLg).

    ./install.sh            # guided: the app, then Neovim and Leader's config if they are missing, then it opens
    ./install.sh --help     # options (--yes, --no-config, --prefix, --uninstall)

The first launch shows the welcome screen: it checks the install and fixes what is missing with Enter.
What is new: CHANGELOG.md. More: https://github.com/sazardev/leader
EOF

tar -C "$DIST" -czf "$DIST/leader-linux-x86_64.tar.gz" "$NAME"
(cd "$DIST" && sha256sum leader-linux-x86_64.tar.gz >leader-linux-x86_64.tar.gz.sha256)
install -m755 "$APP/package/leader-installer.sh" "$DIST/leader-installer.sh"
rm -rf "$STAGE"
ls -la "$DIST"
