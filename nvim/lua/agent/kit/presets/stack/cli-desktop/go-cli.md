<!-- name: Go CLI -->
<!-- desc: command-line tool in Go: cobra, koanf config, slog, golden tests, goreleaser releases -->

# STACK.md: Go CLI

## Summary

A command-line tool written in Go, distributed as one static binary per platform. Commands are a thin layer (cobra)
that parses flags and calls application code; the application code knows nothing about cobra, terminals or files and is
tested directly. Output is stable and scriptable: human output on a TTY, `--json` for machines, errors on stderr with
meaningful exit codes.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Go 1.23+ | Static binaries, cross-compilation |
| Commands | `spf13/cobra` | Subcommands, help, shell completion |
| Config | `knadh/koanf` (file + env + flags) or plain `flag`/env for small tools | Explicit precedence, no global state |
| Logging | `log/slog` to stderr (`--verbose` = debug) | Structured, stdlib |
| Terminal UI | `charmbracelet/lipgloss` (styling) / `bubbletea` only for interactive screens | Optional, isolated |
| HTTP | `net/http` with timeouts | Stdlib |
| Testing | `testing`, golden files (`testdata/*.golden` with `-update`), `rogpeppe/go-internal/testscript` | End-to-end CLI tests |
| Lint | golangci-lint v2 | Strict |
| Release | goreleaser (archives, checksums, Homebrew tap, deb/rpm, SBOM) | One config for all platforms |
| Version info | `-ldflags "-X main.version=..."` / `runtime/debug.ReadBuildInfo` | `tool version` |

## Project layout

```
cmd/tool/main.go                 calls cli.Execute(); exit code from the returned error
internal/
  cli/
    root.go                      root command, global flags, config loading
    sync.go                      `tool sync`: flags → app.Sync(ctx, opts) → render
    list.go                      one command per file
    output.go                    text/JSON renderers, TTY detection
    exitcode.go                  error → exit code mapping
  app/                           use cases, independent of cobra
    sync.go
    list.go
  config/config.go               typed config + koanf loading + validation
  <domain>/                      domain types and logic
  adapters/                      filesystem, HTTP API clients, git…
testdata/
  script/*.txtar                 testscript end-to-end scenarios
  golden/*.golden
.goreleaser.yaml
```

Dependency direction: `cmd → cli → app → domain`; `adapters` implement interfaces defined in `app`/`domain`. Only `cli` imports cobra; only `cli/output.go` writes to stdout.

## Conventions

- One command per file; `RunE` only builds options, calls one app function and renders the result.
- Flags: kebab-case long names, short flags only for the most common; every flag has a help text; env vars `TOOL_<FLAG>`.
- Config precedence: flags > env > config file (`$XDG_CONFIG_HOME/tool/config.yaml`) > defaults.
- stdout is for results, stderr for logs, progress and errors; `--json` output is a stable contract.
- Exit codes: 0 success, 1 runtime error, 2 usage error, documented others.
- `context.Context` from `cmd.Context()` passed everywhere; Ctrl-C cancels cleanly (`signal.NotifyContext`).
- No `os.Exit` outside `main`; no global mutable state.
- New command = `internal/cli/<name>.go` + `internal/app/<name>.go` + tests + docs line in the README.

## Commands

| Task | Command |
| --- | --- |
| Build | `go build -o bin/tool ./cmd/tool` |
| Run | `go run ./cmd/tool --help` |
| Test | `go test ./...` |
| Update goldens | `go test ./... -update` |
| Lint | `golangci-lint run` |
| Format | `gofmt -w .` |
| Release (dry) | `goreleaser release --snapshot --clean` |
| Completion | `tool completion zsh > _tool` |

## Testing

- `app` functions: table-driven unit tests with fakes for adapters.
- Renderers: golden files for text and JSON output (`-update` flag rewrites them; review the diff).
- End-to-end: `testscript` `.txtar` scripts run the real binary with files, env and expected stdout/stderr/exit codes.
- Adapters: `httptest.Server` for HTTP clients; `t.TempDir()` for filesystem work.

## Quality gates

- golangci-lint clean, `go test -race ./...` passes, goldens reviewed.
- `goreleaser check` passes; snapshot release builds for all target platforms in CI.
- `--help` of every command reviewed: examples present, no typos.
- `go mod tidy` leaves no diff.

## Dependencies

- Stdlib first; cobra and koanf are the only framework-like dependencies.
- Do NOT use: viper (global state, heavy), `log.Fatal` in library code, `fmt.Println` for logs, init()-registered commands with side effects, CGO unless required (breaks static builds).

## Rules for agents

- Keep cobra out of `internal/app` and the domain.
- Never write to stdout outside the renderers; logs and progress go to stderr.
- Every new flag: help text, env var, config key if persistent, and a test.
- Never change `--json` output fields in a breaking way without a major version.
- Every command supports `--help` with at least one example (`Example:` field).
- Use `cmd.Context()` and respect cancellation in long operations.
- Update golden files only with `-update` and include the diff in the change.
- Return errors with context; the CLI layer maps them to messages and exit codes.
