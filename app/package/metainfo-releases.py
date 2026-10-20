#!/usr/bin/env python3
"""The <releases> block of the AppStream metadata, from CHANGELOG.md: the newest few versions, each with its Highlights.
usage: metainfo-releases.py CHANGELOG.md [COUNT]  → prints the XML block"""
import re
import sys
from xml.sax.saxutils import escape

text = open(sys.argv[1], encoding="utf-8").read()
count = int(sys.argv[2]) if len(sys.argv) > 2 else 5
sections = re.split(r"(?m)^## \[", text)[1:]
out = ["<releases>"]
for sec in sections[:count]:
    head, _, body = sec.partition("\n")
    m = re.match(r"([\w.\-]+)\]\s*-\s*([\d-]+)", head)
    if not m:
        continue
    version, date = m.groups()
    items = []
    in_highlights = False
    current = None
    for line in body.split("\n"):
        if line.startswith("### "):
            in_highlights = line.strip() == "### Highlights"
            continue
        if not in_highlights:
            continue
        if line.startswith("- "):
            current = [line[2:].strip()]
            items.append(current)
        elif current is not None and line.startswith("  ") and line.strip():
            current.append(line.strip())
    out.append(f'  <release version="{version}" date="{date}">')
    if items:
        out.append("    <description>\n      <ul>")
        for it in items:
            plain = re.sub(r"\*\*(.*?)\*\*", r"\1", " ".join(it))
            plain = re.sub(r"`([^`]*)`", r"\1", plain)
            out.append(f"        <li>{escape(plain)}</li>")
        out.append("      </ul>\n    </description>")
    out.append(f'    <url type="details">https://github.com/sazardev/leader/releases/tag/v{version}</url>')
    out.append("  </release>")
out.append("</releases>")
print("\n".join(out))
