#!/bin/sh
# Regenerates the web documentation (docs/docs/index.html) from the repository's Markdown: README.md, CHEATSHEET.md,
# docs/cheatsheets/ and AGENTS.md. `--check` exits 1 if it is out of date; `--worktree` reads the files as they are on
# disk instead of as they are staged. Only needs nvim (no plugins, no network).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/hermetic.sh"
command -v nvim >/dev/null 2>&1 || { echo "gen-docs: nvim is not in PATH" >&2; exit 2; }
exec nvim -u NONE --headless -l "$ROOT/scripts/gen-docs.lua" "$@"
