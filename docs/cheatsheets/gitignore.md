# .gitignore (`<leader>Gi`)

Writes a `.gitignore` from what the project is made of. 0 tokens, nothing resident. Keys: [`CHEATSHEET.md`](../../CHEATSHEET.md)
(section **Git**, `ignore rules`).

## What it looks at

Marker files and extensions under the git root (3 levels deep; `settings.git.ignore`), never inside dependency or build
folders (`node_modules/`, `vendor/`, `target/`… count by name only). `go.mod` or `*.go` → Go, `package.json` or `*.ts` →
Node, `pubspec.yaml` → Dart/Flutter, `Dockerfile` → Docker, `*.tf` → Terraform… Nothing is read from file contents.

The checklist opens with what it found **checked** and says why (`found go.mod +14`). **Secrets** (`.env*`, keys,
certificates, credentials, password databases) and **Editor and system** (OS files, IDE state, logs) are recommended for
every project; Secrets goes first in the file, Editor and system last. Space or `x` toggles, `a` toggles all, `Enter` writes.

## With a `.gitignore` already there

It **adds only what is missing** and never removes or reorders anything: a rule is not written twice (not even across
topics: `dist/` is in Node, Python and Go but lands once), a block with nothing new disappears with its comment, and a topic
the file already covers is listed as `already in .gitignore`, unchecked. Each row says how many new rules it would add.
It refuses to run while `.gitignore` has unsaved changes in a buffer.

## What git already tracks

Ignoring a file does not untrack it. After writing, it asks git which tracked files the rules now match
(`git ls-files -ci --exclude-standard`) and warns, e.g. a `.env` that was committed long ago: `git rm --cached <file>` stops
tracking it (the secret stays in the history: rotate it).

## Topics

Plain files in `lua/gitignore/presets/<name>.gitignore`; drop one in and it is discovered:

```
# Go: compiled binaries, test and profiling output     <- line 1: `Title: what it ignores`, written as the section header
# detect: go.mod go.work *.go                          <- line 2: what says it applies (not written)
# Binaries and build output                            <- rules in blocks with a comment each
/bin/
```

`detect` takes file names (`go.mod`), globs on a whole name (`*.go`, `.env.*`), folders with a slash (`node_modules/`) and
`always`. Rules that people usually commit on purpose are left out or commented (`Cargo.lock`, `pubspec.lock`,
`google-services.json`, `.vscode/settings.json` is kept); the tests check with `git check-ignore` that none of a long list of
files a project needs is ignored by all topics together, and that secrets and junk are.

Tests: `scripts/test-gitignore.sh`.
