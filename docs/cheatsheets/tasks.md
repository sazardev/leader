# Makefile tasks (`<leader>R`)

The targets of the project's `Makefile` in one picker, run in the integrated terminal. It asks `make`, so it costs
**0 tokens** and nothing stays running. Keys: [`CHEATSHEET.md`](../../CHEATSHEET.md) (section **Run**).

**It works with a Makefile and only with a Makefile.** Without one, every key says so and does nothing, except
`<leader>Rc`, which creates one.

## Which Makefile

The nearest `GNUmakefile`, `makefile` or `Makefile` from the current file's folder **up to the git root**, never above it
(the `~/Makefile` of the machine is not your project's). In a monorepo, a Makefile in the subfolder wins over the root's.

## What is a task

A target is listed when it is `.PHONY` or has a description. Descriptions come from the file's text:

```make
.PHONY: build test

build: ## Build everything        <- inline description
test: build
	go test ./...

# Remove the build output            <- a comment right above works too
clean:
	rm -rf out
```

`.PHONY` targets declared in `include`d files are found too (the list comes from `make -qp`, which prints make's
database and runs nothing). Without GNU make (Windows, BSD) only the file's text is parsed. A Makefile with neither
`.PHONY` nor descriptions lists every plain target.

## Picker

| Key | Does |
|---|---|
| `Enter` | run the target |
| `Ctrl-a` | ask for arguments, then run (`PKG=./x`, `-j8`) |
| `Ctrl-p` | dry run: `make -n`, prints what it would do |
| `Ctrl-r` | read the Makefile again (the list is cached until it changes) |

The dot marks the default goal; `<leader>Rd` runs a bare `make`.

## Create a Makefile (`<leader>Rc`)

Only where there is none. Pick a language (the one the project looks like comes first: `go.mod`, `Cargo.toml`,
`package.json`, `pubspec.yaml`…) and then a preset, with the file as preview. It is written to the project root (the git
root) and opened. It never overwrites a Makefile.

| Language | Presets |
|---|---|
| Go | `basic`, `service` (live reload, race, coverage, image), `cli` (cross-compile), `library` (bench, coverage report) |
| Python | `venv`, `uv`, `fastapi`, `django` |
| Rust | `basic`, `full` (watch, audit, coverage, bench) |
| TypeScript / Node | `npm`, `pnpm`, `nextjs` |
| Dart / Flutter | `flutter`, `dart` |
| Java | `maven`, `gradle` |
| Kotlin | `gradle` (ktlint, detekt) |
| C / C++ | `c`, `cpp` (sources in `src/`, objects in `obj/`), `cmake` |
| Docker | `compose`, `image` |
| Shell | `basic` (shellcheck, shfmt, bats) |

Every preset has a `help` target (`make help` prints each target and what it does) and descriptions on all of them, so
the picker shows them at once.

**Add your own**: drop `presets/<language>/<name>.mk` in `nvim/lua/tasks/` (a new folder is a new language). The first
line is a `# description` comment (it stays in the created Makefile), every target has `## text`, recipes use **tabs**.
`scripts/test-tasks.sh` runs a real `make` over every preset.

## Good to know

- Targets run in the **same terminal** as `<leader>ao` reads, so a failing build can go straight to the agent's "fix from
  output". `<leader>Rq` puts the file:line errors of that output in the quickfix for free.
- If a target is still running, the next one asks before it is typed into it (`Stop it and run`). `<leader>Rs` sends Ctrl-C.
- `<leader>Rl` repeats the last target of the project (it survives a restart); `<leader>Ra` edits its arguments first.
