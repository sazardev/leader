<!-- name: Go TUI (Bubble Tea) -->
<!-- desc: terminal UI in Go with Charm: Bubble Tea, Bubbles, Lip Gloss, Huh, Glamour; teatest golden tests -->

# STACK.md: Go TUI (Bubble Tea)

## Summary

A TUI (terminal user interface) application in Go built on Charm's Bubble Tea, which follows the Elm architecture: a
`Model` holds state, `Update` turns messages into a new model plus commands, `View` renders a string. Side effects
(IO, timers, HTTP) run only inside `tea.Cmd`s and come back as messages. The screen is a tree of small components, each
with its own model, messages and view; the domain logic lives outside the UI and is plain, testable Go.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Go 1.25+ | One static binary, fast startup, trivial cross-compilation |
| TUI runtime | `github.com/charmbracelet/bubbletea` | Elm architecture: predictable state, side effects as commands |
| Components | `github.com/charmbracelet/bubbles` (list, table, textinput, viewport, spinner, help, key) | Tested building blocks with key bindings and help |
| Styling | `github.com/charmbracelet/lipgloss` | Declarative styles, layout (`JoinHorizontal`, `Place`), adaptive colors |
| Forms | `github.com/charmbracelet/huh` | Prompts and multi-step forms that embed in a Bubble Tea program |
| Markdown | `github.com/charmbracelet/glamour` | Renders help, docs and previews in the terminal |
| CLI entry | `github.com/spf13/cobra` (or `flag` for one command) | Subcommands, flags, completions |
| Config | TOML/YAML in `os.UserConfigDir()` + env overrides | Follows the platform's conventions |
| Logging | `log/slog` to a file (`tea.LogToFile`) | stdout belongs to the UI |
| Testing | `testing` + `github.com/charmbracelet/x/exp/teatest` (golden files) | Whole-program tests with final output snapshots |
| Lint | golangci-lint v2 | One config, many linters |
| Release | GoReleaser | Binaries for every OS, Homebrew/Scoop, checksums |

## Project layout

```
cmd/app/main.go                  flags/cobra, config load, builds the root model, tea.NewProgram(...).Run()
internal/
  domain/                        plain Go: types and rules, no Bubble Tea imports
    task.go                      Task entity and its invariants
    store.go                     TaskStore port (interface)
  storage/
    file_store.go                implements TaskStore (JSON/SQLite on disk)
  ui/
    app.go                       root model: owns the active screen, routes messages, global keys (quit, help)
    keys.go                      key.Binding map shared by help views
    styles.go                    every lipgloss.Style and color in one place (adaptive light/dark)
    msgs.go                      app-wide messages (errMsg, tasksLoadedMsg, windowSizeMsg handling)
    commands.go                  tea.Cmd constructors that call the domain/storage (loadTasks, saveTask)
    screens/
      list/
        model.go                 list screen: Model, Init
        update.go                Update: messages → new state + commands
        view.go                  View: pure rendering from the model
      detail/{model,update,view}.go
      edit/form.go               huh form embedded as a component
    components/
      statusbar.go               one reusable component per file
testdata/                        teatest golden files (*.golden)
```

Dependency direction: `cmd → ui → domain ← storage`. `domain` never imports Bubble Tea or Lip Gloss; screens never
import each other: they talk through messages handled by `app.go`.

## Conventions

- One component per folder or file; each one exposes `New(...) Model`, `Init() tea.Cmd`, `Update(tea.Msg) (Model, tea.Cmd)` and `View() string`.
- `View` is pure: it reads the model and returns a string. No IO, no time, no randomness in `View` or `Update`.
- Every side effect is a `tea.Cmd` returning a typed message; errors come back as `errMsg{err}` and are shown, never `panic`.
- Children are updated by the parent forwarding messages; the parent batches child commands with `tea.Batch`.
- `tea.WindowSizeMsg` is stored in the root and passed down; components never assume a terminal size.
- Styles and colors only from `ui/styles.go`; use `lipgloss.AdaptiveColor` so light and dark terminals both work.
- Key bindings are `key.Binding`s with help text; the help bubble shows them, so every key is discoverable.
- New screen = a folder under `ui/screens/` with model/update/view + its messages + a route in `app.go` + a teatest test.

## Commands

| Task | Command |
| --- | --- |
| Run | `go run ./cmd/app` |
| Build | `go build -o bin/app ./cmd/app` |
| Test | `go test ./...` |
| Update golden files | `go test ./internal/ui/... -update` |
| Lint | `golangci-lint run` |
| Format | `gofmt -w .` |
| Debug log | `DEBUG=1 go run ./cmd/app` then `tail -f debug.log` |
| Release (dry run) | `goreleaser release --snapshot --clean` |

## Testing

- Domain and storage: table-driven unit tests, no terminal involved.
- `Update` functions: call them directly with a message and assert on the returned model and the command's message.
- Whole program: `teatest.NewTestModel` with a fixed size (`teatest.WithInitialTermSize(80, 24)`), send keys, wait for output, compare the final output with a golden file.
- Force a stable color profile in tests (`lipgloss.SetColorProfile(termenv.Ascii)`) so golden files do not depend on the terminal.
- A bug fix starts with a failing test that reproduces the key sequence.

## Quality gates

- `gofmt` clean, `golangci-lint run` with zero issues (errcheck, govet, staticcheck, revive, gocritic).
- `go test -race ./...` passes and golden files are committed and up to date.
- The binary starts in under 100 ms and never writes to stdout outside the program (logs go to a file).

## Dependencies

- Charm libraries for the UI, the standard library for everything else.
- Allowed: the table above. Anything else needs a reason in the PR.
- Do NOT use: tview/termui/gocui alongside Bubble Tea (two UI models), `fmt.Print` while the program runs (corrupts the screen), global mutable state shared between components, goroutines that write to the model directly (send a message with `p.Send` or a command instead).

## Rules for agents

- Never do IO, sleep or read the clock in `Update` or `View`: return a `tea.Cmd` that produces a message.
- Never mutate a model from a goroutine; results always come back as messages.
- Never print to stdout/stderr while the program runs; log to the file set up with `tea.LogToFile`.
- Every new style or color goes in `ui/styles.go`; never inline `lipgloss.NewStyle()` in a view.
- Every new key gets a `key.Binding` with help text and appears in the help view.
- Handle `tea.WindowSizeMsg` in every component that lays out content; test at 80×24 and a narrow width.
- Keep `domain` free of UI imports; a screen calls the domain only through commands in `ui/commands.go`.
- Every new screen gets a teatest golden test; regenerate golden files only when the change is intended and say so.
- Quit cleanly on `ctrl+c` and `q`, restoring the terminal (no `os.Exit` inside the program).
