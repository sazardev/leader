#!/usr/bin/env bash
# Build the downloadable documentation pack: docs/downloads/leader-docs.zip (stable URL) and
# docs/downloads/leader-docs-VERSION.zip (release asset). The contents come from scripts/docs-bundle.txt — the SAME
# list the `leader` binary embeds — so the web download and the offline copy are the same documentation.
# The ZIP is generated, not committed: .gitignore excludes docs/downloads/. No build step, no dependencies:
#   ./scripts/pack-docs.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION")"
OUT="$ROOT/docs/downloads"
mkdir -p "$OUT"

python3 - "$ROOT" "$VERSION" "$OUT/leader-docs-$VERSION.zip" "$ROOT/scripts/docs-bundle.txt" <<'PY'
import sys
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

root, version, out, manifest = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3]), Path(sys.argv[4])
files = [line.strip() for line in manifest.read_text(encoding="utf-8").splitlines() if line.strip() and not line.startswith("#")]
missing = [rel for rel in files if not (root / rel).is_file()]
if missing:
    raise SystemExit(f"pack-docs: missing from the bundle: {', '.join(missing)}")

index = (
    f"Leader {version} — offline documentation\n"
    f"{'=' * 40}\n\n"
    "Open docs/offline.html in a browser: the whole guide, every cheat sheet and the search work without a network.\n"
    "Open docs/docs/index.html for the generated web documentation.\n"
    "docs/cheatsheets/*.md are the per-language quick references.\n\n"
    "Contents:\n" + "\n".join("  " + rel for rel in files) + "\n"
)

def add(z, name, data):
    info = ZipInfo(name, (1980, 1, 1, 0, 0, 0))  # reproducible: no timestamps, no host-specific bits
    info.compress_type = ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    z.writestr(info, data)

with ZipFile(out, "w") as z:
    add(z, "INDEX.txt", index.encode("utf-8"))
    for rel in files:
        add(z, rel, (root / rel).read_bytes())
PY

cp "$OUT/leader-docs-$VERSION.zip" "$OUT/leader-docs.zip"
printf 'pack-docs: %s (%s files, %s)\n' "$OUT/leader-docs-$VERSION.zip" "$(wc -l < "$ROOT/scripts/docs-bundle.txt")" "$(du -h "$OUT/leader-docs-$VERSION.zip" | cut -f1)"
