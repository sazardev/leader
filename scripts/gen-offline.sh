#!/bin/sh
# Builds the offline guide: docs/offline.html is the generated documentation page with the two fonts and the icons
# embedded as data URIs, no network needed. `--check` exits 1 when it is out of date (the pre-commit hook and CI call it).
# Only needs python3; the page itself is generated first by scripts/gen-docs.sh.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "gen-offline: python3 is not in PATH" >&2; exit 2; }

exec python3 - "$ROOT" "$@" <<'PY'
import base64
import sys
from pathlib import Path

root = Path(sys.argv[1])
check = "--check" in sys.argv[2:]
src = root / "docs/docs/index.html"
out = root / "docs/offline.html"

html = src.read_text(encoding="utf-8")


def data(path: str, mime: str) -> str:
    return f"data:{mime};base64," + base64.b64encode((root / path).read_bytes()).decode()


# The two self-hosted fonts (the page already has the CSS inline).
for name in ("Geist-Variable.woff2", "GeistMono-Variable.woff2"):
    html = html.replace(f"url(../fonts/{name})", f"url({data(f'docs/fonts/{name}', 'font/woff2')})")

# Preloads are pointless once the font is inside the file; icons become data URIs too.
html = html.replace(
    '<link rel="preload" href="../fonts/Geist-Variable.woff2" as="font" type="font/woff2" crossorigin>\n', ""
)
html = html.replace(
    '<link rel="preload" href="../fonts/GeistMono-Variable.woff2" as="font" type="font/woff2" crossorigin>\n', ""
)
html = html.replace('href="../apple-touch-icon.png"', f'href="{data("docs/apple-touch-icon.png", "image/png")}"')
html = html.replace('href="../icon-192.png"', f'href="{data("docs/icon-192.png", "image/png")}"')
html = html.replace('href="../"', 'href="https://leader.sazardev.stream/"')

# A downloadable copy must not compete with the live docs in search results; its canonical stays the live page.
html = html.replace(
    '<meta name="robots" content="index,follow,max-image-preview:large">',
    '<meta name="robots" content="noindex,follow">',
)
html = html.replace("<title>Docs — Leader</title>", "<title>Leader — offline guide</title>")
html = html.replace(
    "<footer>Generated from", "<footer>Offline copy — the fonts are embedded; links to the live site need a connection. Generated from", 1
)

if check:
    current = out.read_text(encoding="utf-8") if out.exists() else ""
    if current != html:
        print("docs/offline.html is out of date: run scripts/gen-offline.sh", file=sys.stderr)
        sys.exit(1)
    print("docs/offline.html is up to date")
else:
    out.write_text(html, encoding="utf-8")
    print(f"docs/offline.html: {len(html) // 1024} KB (fonts and icons embedded)")
PY
