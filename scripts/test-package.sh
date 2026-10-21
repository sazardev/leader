#!/usr/bin/env bash
# The desktop app's packaging (app/package*, app/assets, packaging/): metadata, icons, the staged file tree, the
# installer scripts, the PKGBUILDs and that every place that names the signing key names the same one. No build, no
# network (package.sh itself, which compiles and signs, is run by hand at release time: see packaging/README.md).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/hermetic.sh"
APP="$ROOT/app"
fails=0
ok() { echo "ok   $1"; }
fail() { echo "FAIL $1${2:+: $2}"; fails=$((fails + 1)); }
check() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else fail "$1" "$2"; fi; }

ID=io.github.sazardev.Leader
# ── metadata ────────────────────────────────────────────────────────────────
if command -v desktop-file-validate >/dev/null 2>&1; then
  check "the .desktop file is valid" "desktop-file-validate '$APP/assets/$ID.desktop'"
else
  echo "skip desktop-file-validate is not installed"
fi
check "the .desktop file is named after the application id and the window class" \
  "grep -q '^StartupWMClass=$ID\$' '$APP/assets/$ID.desktop' && grep -q 'APP_ID: &str = \"$ID\"' '$APP/crates/leader-gui/src/platform.rs'"
check "the AppStream metadata is well-formed and its id, launchable and icon agree" \
  "python3 - <<PY
import xml.etree.ElementTree as ET
r = ET.parse('$APP/assets/$ID.metainfo.xml').getroot()
assert r.find('id').text == '$ID'
assert r.find('launchable').text == '$ID.desktop'
assert r.find('icon').text == 'leader'
assert r.find('metadata_license').text and r.find('project_license').text == 'MIT'
assert len(r.findall('screenshots/screenshot')) >= 3
PY"
if command -v groff >/dev/null 2>&1; then
  check "the manual pages are valid roff" "for p in leader.1 leader-setup.1; do ! groff -man -Tutf8 -ww -z '$APP/assets'/\$p 2>&1 | grep -qiE 'error|warning'; done"
else
  echo "skip groff is not installed"
fi

# ── icons ───────────────────────────────────────────────────────────────────
for size in 16 22 24 32 48 64 128 256 512; do
  f="$APP/assets/icons/hicolor/${size}x${size}/apps/leader.png"
  check "icon ${size}px is a ${size}x${size} PNG" "[ \"\$(python3 -c \"import struct,sys; d=open('$f','rb').read(24); print(struct.unpack('>II', d[16:24]))\")\" = '($size, $size)' ]"
done
check "the window icon is 128x128 RGBA" "[ \$(stat -c %s '$APP/assets/window-icon-128.rgba') -eq 65536 ]"

# ── the staged tree ─────────────────────────────────────────────────────────
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf '#!/bin/sh\necho leader\n' >"$tmp/fake-leader"
chmod +x "$tmp/fake-leader"
VERSION="$(cat "$ROOT/VERSION")"
bash "$APP/package/stage-tree.sh" "$tmp/fake-leader" "$tmp/usr" "$VERSION" >/dev/null 2>"$tmp/err"
check "stage-tree.sh runs" "[ ! -s '$tmp/err' ]"
for f in bin/leader bin/leader-setup share/applications/$ID.desktop share/metainfo/$ID.metainfo.xml \
  share/man/man1/leader.1.gz share/man/man1/leader-setup.1.gz share/doc/leader-editor/copyright \
  share/doc/leader-editor/changelog.gz share/icons/hicolor/scalable/apps/leader.svg share/icons/hicolor/256x256/apps/leader.png; do
  check "the tree has $f" "[ -f '$tmp/usr/$f' ]"
done
check "the program and leader-setup are executable" "[ -x '$tmp/usr/bin/leader' ] && [ -x '$tmp/usr/bin/leader-setup' ]"
check "no placeholder is left in what is installed" "! grep -rlE '@(BIN|VERSION)@' '$tmp/usr'"
check "leader-setup carries the version it was built from" "grep -q 'VERSION=\"$VERSION\"' '$tmp/usr/bin/leader-setup'"
check "the menu entry runs the program from PATH" "grep -q '^Exec=leader %F\$' '$tmp/usr/share/applications/$ID.desktop'"
check "the AppStream releases include this version" "grep -q 'release version=\"$VERSION\"' '$tmp/usr/share/metainfo/$ID.metainfo.xml'"
check "the AppStream result is well-formed" "python3 -c \"import xml.etree.ElementTree as ET; ET.parse('$tmp/usr/share/metainfo/$ID.metainfo.xml')\""
check "the changelog in the tree is this version's" "zcat '$tmp/usr/share/doc/leader-editor/changelog.gz' | head -1 | grep -q '\[$VERSION\]'"

# ── scripts ─────────────────────────────────────────────────────────────────
for s in app/package.sh app/install.sh app/package/install.sh app/package/stage-tree.sh app/package/leader-installer.sh; do
  check "$s parses" "bash -n '$ROOT/$s'"
done
check "leader-setup parses" "sh -n '$APP/package/leader-setup'"
check "the installer's --help works" "bash '$APP/package/install.sh' --help"

# ── the signing key is the same everywhere ───────────────────────────────────
if command -v gpg >/dev/null 2>&1; then
  fpr="$(gpg --show-keys --with-colons "$ROOT/packaging/leader-releases.asc" 2>/dev/null | awk -F: '/^fpr/ { print $10; exit }')"
  check "the public key is in the repository" "[ -n '$fpr' ]"
  check "the installer pins that key" "grep -q 'FPR=\"$fpr\"' '$APP/package/leader-installer.sh'"
  for p in leader-editor-bin; do
    check "$p's validpgpkeys is that key" "grep -q \"validpgpkeys=('$fpr')\" '$ROOT/packaging/arch/$p/PKGBUILD'"
  done
  expiry="$(gpg --show-keys --with-colons "$ROOT/packaging/leader-releases.asc" 2>/dev/null | awk -F: '/^pub/ { print $7; exit }')"
  check "the key has not expired (and expires in more than 90 days)" "[ -n '$expiry' ] && [ '$expiry' -gt \$(( \$(date +%s) + 90*86400 )) ]"
  check "packaging/README.md names that key" "grep -q '8E43 7A79 36E4 8EAE DA88  CD73 A7DC C3DB B671 476A' '$ROOT/packaging/README.md'"
fi

# ── Arch ────────────────────────────────────────────────────────────────────
for p in leader-editor-bin leader-editor; do
  check "$p/PKGBUILD parses" "bash -n '$ROOT/packaging/arch/$p/PKGBUILD'"
  if command -v makepkg >/dev/null 2>&1; then
    check "$p/PKGBUILD makes a .SRCINFO" "(cd '$ROOT/packaging/arch/$p' && makepkg --printsrcinfo | grep -q 'pkgbase = $p')"
  fi
done
check "the source PKGBUILD stages through stage-tree.sh" "grep -q 'app/package/stage-tree.sh' '$ROOT/packaging/arch/leader-editor/PKGBUILD'"
check "there is a LICENSE and the PKGBUILDs say MIT" "[ -f '$ROOT/LICENSE' ] && grep -q \"license=('MIT')\" '$ROOT/packaging/arch/leader-editor/PKGBUILD'"

echo
if [ "$fails" = 0 ]; then echo "ALL OK"; else echo "FAILURES: $fails"; exit 1; fi
