<!-- name: Rust CLI -->
<!-- desc: command-line tool in Rust: clap derive, anyhow/thiserror, tracing, assert_cmd + insta, cargo-dist -->

# STACK.md: Rust CLI

## Summary

A fast, single-binary command-line tool in Rust. The crate is split into a library (`lib.rs`: all logic, typed errors,
testable) and a thin binary (`main.rs`: argument parsing with clap, error reporting, exit codes). Output is scriptable:
human-readable by default, `--json` for machines, diagnostics on stderr.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Rust stable (2021/2024 edition), MSRV pinned in `Cargo.toml` | Safety, speed |
| Arguments | `clap` v4 (derive) + `clap_complete` | Typed args, help, completions |
| Errors | `thiserror` in the library, `anyhow` in the binary | Typed errors inside, context at the edge |
| Logging | `tracing` + `tracing-subscriber` (stderr, `-v` levels) | Structured diagnostics |
| Serialization | `serde` + `serde_json` / `toml` | Config and `--json` output |
| Config | `directories` (XDG paths) + serde | Platform paths |
| Async (only if needed) | `tokio` (current-thread) + `reqwest` | Network-heavy tools only |
| Terminal | `anstream`/`owo-colors`, `indicatif` (progress) | Colors that respect `NO_COLOR` |
| Testing | `cargo test`, `assert_cmd` + `predicates`, `insta` snapshots, `tempfile` | End-to-end binary tests |
| Lint/format | `clippy` (pedantic selectively), `rustfmt` | Strict |
| Supply chain | `cargo-deny` (licenses, advisories, duplicates) | Safe dependencies |
| Release | `cargo-dist` (installers, GitHub releases, Homebrew) | Cross-platform artifacts |

## Project layout

```
Cargo.toml
src/
  main.rs                     parse Cli, init tracing, call run(), map errors to exit codes
  cli.rs                      clap derive structs: Cli, Command enum, args per subcommand
  lib.rs                      pub mod declarations, public API
  commands/
    mod.rs
    sync.rs                   one subcommand per file: fn run(args, ctx) -> Result<Output>
    list.rs
  output.rs                   text and JSON rendering
  config.rs                   config file + defaults
  error.rs                    thiserror Error enum
  domain/                     core types and logic, no IO
  io/                         filesystem, network adapters (traits + impls)
tests/
  cli.rs                      assert_cmd end-to-end tests
  snapshots/                  insta snapshots
deny.toml
```

Dependency direction: `main → cli, commands → domain`; `commands` use `io` through traits. `domain` performs no IO; only `main.rs` and `output.rs` touch stdout.

## Conventions

- One subcommand per file; each returns a typed result rendered by `output.rs`.
- Library code returns `Result<T, Error>` (thiserror); `anyhow::Context` only in the binary layer.
- No `unwrap()`/`expect()` outside tests and truly impossible states (with a message saying why).
- stdout for results, stderr for logs and errors; respect `NO_COLOR` and non-TTY output.
- Exit codes: 0 ok, 1 failure, 2 usage (clap's default); documented in `--help`.
- Borrow over clone; `&str`/`&Path` parameters, owned types in structs.
- New subcommand = variant in `cli.rs` + `commands/<name>.rs` + test in `tests/cli.rs` + snapshot.

## Commands

| Task | Command |
| --- | --- |
| Build | `cargo build --release` |
| Run | `cargo run -- --help` |
| Test | `cargo test` |
| Review snapshots | `cargo insta review` |
| Lint | `cargo clippy --all-targets --all-features -- -D warnings` |
| Format | `cargo fmt` |
| Dependencies audit | `cargo deny check` |
| Release plan | `dist plan` / `dist build` |

## Testing

- Domain logic: unit tests in the same file (`#[cfg(test)] mod tests`).
- Adapters: tests with `tempfile` directories and trait fakes.
- End-to-end: `assert_cmd::Command::cargo_bin("tool")` with args, env and stdin; assert exit code and output with `predicates`.
- Output formats: `insta` snapshots for text and JSON (`assert_snapshot!`, `assert_json_snapshot!`).
- Property tests (`proptest`) for parsers and pure transformations when inputs are rich.

## Quality gates

- `cargo fmt --check`, `cargo clippy -- -D warnings` and `cargo test` pass on Linux, macOS and Windows in CI.
- `cargo deny check` clean (advisories, licenses, bans).
- MSRV build passes; snapshots reviewed, never blindly accepted.
- No `unsafe` without a `// SAFETY:` comment and a reason.

## Dependencies

- Prefer small, widely used crates; check maintenance and compile-time cost before adding one.
- Disable default features you do not need.
- Do NOT use: `anyhow` inside the library API, `structopt` (merged into clap), `lazy_static` (use `std::sync::LazyLock`), async runtimes for tools that do no network IO, `openssl` when `rustls` works.

## Rules for agents

- Keep parsing in `cli.rs` and logic in the library; `main.rs` stays tiny.
- Never `unwrap()` on user input, IO or parsing results.
- Every new flag gets help text and an end-to-end test.
- Update snapshots with `cargo insta review` and keep the diff in the change.
- Never print to stdout from library code; return data, let `output.rs` render it.
- Keep `--json` output backwards compatible.
- Run clippy with `-D warnings` before declaring a change done.
- Add new dependencies with a reason; run `cargo deny check` after.
