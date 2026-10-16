<!-- name: Rust TUI (Ratatui) -->
<!-- desc: terminal UI in Rust: Ratatui + crossterm, components with actions, tokio events, insta snapshots -->

# STACK.md: Rust TUI (Ratatui)

## Summary

A TUI (terminal user interface) application in Rust built on Ratatui with the crossterm backend. Ratatui is immediate
mode: every frame the UI is drawn from the application state. The app follows a component pattern: terminal events
become `Action`s, components handle actions to update their state, and `draw` renders them. A tokio runtime drives an
event loop (input, ticks, render) and background tasks that report back through an action channel. Domain logic is a
separate module with no Ratatui imports.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Rust stable, edition 2024 | Fast, memory-safe, one binary |
| TUI | `ratatui` (with `crossterm` backend) | De-facto Rust TUI library, immediate-mode widgets |
| Terminal / input | `crossterm` (event-stream feature) | Cross-platform raw mode, keys, mouse, resize |
| Async | `tokio` (rt-multi-thread, macros, sync, time) | Event loop, background tasks, channels |
| Errors | `color-eyre` (app), `thiserror` (domain) | Pretty reports; typed errors where callers match on them |
| CLI | `clap` (derive) | Flags, subcommands, help |
| Config | `serde` + `toml` in `directories::ProjectDirs` config dir | Platform config paths |
| Logging | `tracing` + `tracing-subscriber` + `tracing-appender` to a file | stdout belongs to the UI |
| Testing | `cargo test` + `insta` snapshots of `TestBackend` buffers | Render output checked as text |
| Lint | `cargo clippy -- -D warnings`, `cargo fmt` | Zero warnings |
| Release | `cargo-dist` | Installers and binaries for every OS |

## Project layout

```
src/
  main.rs                 parse CLI, install color-eyre and tracing, run App
  app.rs                  App: main loop (select over events, actions, render), owns components and mode
  tui.rs                  terminal setup/restore (raw mode, alternate screen), event stream → Event, panic hook
  event.rs                Event enum: Key, Mouse, Resize, Tick, Render
  action.rs               Action enum: everything that can happen (Quit, Refresh, Select(usize), DataLoaded(...), Error(String))
  config.rs               key bindings and settings (serde)
  components/
    mod.rs                Component trait: handle_key → Option<Action>, update(Action) → Option<Action>, draw(&mut Frame, Rect)
    list.rs               one component per file
    details.rs
    status_bar.rs
  domain/
    mod.rs                types and rules, no ratatui
    store.rs              data access (files, HTTP, DB) behind a trait
  theme.rs                every Style/Color in one place
tests/
  render.rs               snapshot tests with TestBackend
  snapshots/              insta .snap files
```

Dependency direction: `main → app → components → domain`. `domain` never imports ratatui or crossterm; components never
call each other: they emit actions the app routes.

## Conventions

- Input never mutates state directly: keys map to `Action`s (from `config.rs` bindings), actions update state.
- `draw` only reads state and renders; no IO, no blocking, no allocations that can be avoided in hot paths.
- Slow work runs in `tokio::spawn`ed tasks that send an `Action` back through the `mpsc::UnboundedSender<Action>`.
- The terminal is always restored: a panic hook and `Drop` on the `Tui` leave raw mode and the alternate screen.
- Layout with `Layout::vertical/horizontal` and constraints; components receive their `Rect` and never assume a size.
- Styles only from `theme.rs`.
- New component = file in `components/` implementing `Component` + its actions in `action.rs` + a snapshot test.

## Commands

| Task | Command |
| --- | --- |
| Run | `cargo run` |
| Build | `cargo build --release` |
| Test | `cargo test` |
| Review snapshots | `cargo insta review` |
| Lint | `cargo clippy --all-targets -- -D warnings` |
| Format | `cargo fmt` |
| Logs | `tail -f $(app --log-path)` (or the path printed by `--help`) |

## Testing

- Domain: plain unit tests in `domain/` modules.
- Components: feed actions, then draw into `Terminal::new(TestBackend::new(80, 24))` and snapshot `terminal.backend()` with `insta::assert_snapshot!`.
- Key mapping: unit tests that a key event produces the expected `Action`.
- Background tasks: test the async functions directly with `#[tokio::test]`, not through the UI.
- Snapshots are reviewed (`cargo insta review`) and committed; never accept them blindly.

## Quality gates

- `cargo fmt --check` and `cargo clippy --all-targets -- -D warnings` clean.
- `cargo test` passes with no pending snapshots (`cargo insta test --check` in CI).
- No `unwrap()`/`expect()` outside tests and `main` setup.

## Dependencies

- ratatui, crossterm, tokio, color-eyre, clap, serde, tracing, insta; anything else needs a reason.
- Do NOT use: `println!` while the TUI runs, blocking IO on the render loop, `termion` alongside crossterm, `unsafe` without a comment proving it sound, global mutable statics for app state.

## Rules for agents

- Never print to stdout/stderr while the TUI is active; use `tracing` to the log file.
- Never block the event loop: anything slower than a frame goes to a spawned task that returns an `Action`.
- Always restore the terminal on exit and on panic; keep the panic hook installed in `tui.rs`.
- A component changes state only in `update(Action)`; key handling only maps keys to actions.
- Keep `domain` free of ratatui/crossterm imports.
- Every new style goes in `theme.rs`; never inline colors in a component.
- Every new component gets an insta snapshot at 80×24 and at a narrow width.
- Return `color_eyre::Result` from the app, `thiserror` enums from the domain; no `unwrap()` in non-test code.
