#!/usr/bin/env bash
# The app's icon set from assets/leader.svg (the brand's heavy N): hicolor PNGs for menus and launchers, and the raw RGBA
# the window embeds (X11 and Windows take their window icon from the program; Wayland takes it from the .desktop file).
# Needs rsvg-convert (librsvg) and ImageMagick. Re-run when the logo changes and commit the result.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
for size in 16 22 24 32 48 64 128 256 512; do
  dir="icons/hicolor/${size}x${size}/apps"
  mkdir -p "$dir"
  # small sizes get the solid N (the dotted one turns to mush under 128 px)
  src=leader.svg
  [ "$size" -le 64 ] && src=leader-small.svg
  rsvg-convert -w "$size" -h "$size" "$src" -o "$dir/leader.png"
done
mkdir -p icons/hicolor/scalable/apps
cp leader.svg icons/hicolor/scalable/apps/leader.svg
# the window icon: 128x128, 8-bit RGBA, no header (crates/leader-gui/src/main.rs include_bytes!s it)
magick icons/hicolor/128x128/apps/leader.png -depth 8 rgba:window-icon-128.rgba
ls -la icons/hicolor/*/apps/ window-icon-128.rgba | head -30
