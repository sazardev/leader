#!/usr/bin/env bash
# The app's installed files, laid out under a prefix: the ONE place that says what Leader installs. Used by package.sh
# (the tarball and the .deb), by app/install.sh (a build from source) and by the Arch PKGBUILDs.
#
#   stage-tree.sh BINARY DEST VERSION [ROOT]
#     BINARY   the built `leader`
#     DEST     the prefix to fill (/usr for a system package: it gets bin/ and share/)
#     VERSION  written into leader-setup and the AppStream releases
#     ROOT     the repository (default: two folders up from this script)
set -euo pipefail
APP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${1:?stage-tree.sh BINARY DEST VERSION}"
D="${2:?stage-tree.sh BINARY DEST VERSION}"
VERSION="${3:?stage-tree.sh BINARY DEST VERSION}"
ROOT="${4:-$(dirname "$APP")}"
APP_ID="io.github.sazardev.Leader"

install -Dm755 "$BIN" "$D/bin/leader"
mkdir -p "$D/bin"
sed "s|@VERSION@|$VERSION|" "$APP/package/leader-setup" >"$D/bin/leader-setup"
chmod 755 "$D/bin/leader-setup"

# the menu entry finds the program on PATH (installers that put it elsewhere rewrite the Exec lines)
mkdir -p "$D/share/applications"
sed "s|@BIN@|leader|g" "$APP/assets/$APP_ID.desktop" >"$D/share/applications/$APP_ID.desktop"
chmod 644 "$D/share/applications/$APP_ID.desktop"

(cd "$APP/assets/icons" && find hicolor -type f) | while read -r f; do
  install -Dm644 "$APP/assets/icons/$f" "$D/share/icons/$f"
done

# AppStream metadata with the release notes between the markers
mkdir -p "$D/share/metainfo"
python3 - "$APP" "$ROOT" "$D/share/metainfo/$APP_ID.metainfo.xml" <<'PY'
import re, subprocess, sys
app, root, out = sys.argv[1:4]
xml = open(f"{app}/assets/io.github.sazardev.Leader.metainfo.xml", encoding="utf-8").read()
rel = subprocess.run(["python3", f"{app}/package/metainfo-releases.py", f"{root}/CHANGELOG.md", "5"], capture_output=True, text=True, check=True).stdout.strip()
xml = re.sub(r"<!--RELEASES-->.*?<!--/RELEASES-->", lambda m: rel, xml, flags=re.S)
open(out, "w", encoding="utf-8").write(xml)
PY
chmod 644 "$D/share/metainfo/$APP_ID.metainfo.xml"

mkdir -p "$D/share/man/man1"
for page in leader.1 leader-setup.1; do
  gzip -9n -c "$APP/assets/$page" >"$D/share/man/man1/$page.gz"
  chmod 644 "$D/share/man/man1/$page.gz"
done

install -Dm644 "$ROOT/LICENSE" "$D/share/doc/leader-editor/copyright"
awk -v v="## [$VERSION]" 'index($0, v) == 1 { on = 1; print; next } on && /^## \[/ { exit } on' "$ROOT/CHANGELOG.md" |
  gzip -9n >"$D/share/doc/leader-editor/changelog.gz"
chmod 644 "$D/share/doc/leader-editor/changelog.gz"
