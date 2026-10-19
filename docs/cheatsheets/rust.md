# Rust

Filetype: `rust`. Pack `rust`.

## Tools

| What | With |
|---|---|
| LSP | `rust-analyzer` with **clippy** as its check (lints as diagnostics, not only compiler errors), proc macros, inlay hints |
| Format on save | `rustfmt` (from the toolchain: `rustup component add rustfmt`) |
| Debug | `codelldb` (Mason) |
| Treesitter | `rust`, `toml` |

## `<leader>r` menu (only in `*.rs`)

The keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md). What they do, at the crate root (`Cargo.toml`):

- **cargo**: run, build, check, clippy (all targets), clippy `--fix`, add/remove crates (what you type:
  `serde --features derive`), update, `doc --open`.
- **Tests in the editor**: the `#[test]` function under the cursor (`#[tokio::test]`, `#[rstest]` too) or the `mod`
  around it, by its path (`calc::tests::adds`, `--exact`), the file's module, the crate, the last run again. Integration
  tests (`tests/x.rs`) run as their own target. Marks per test, a failure is a diagnostic on the line it panicked at
  with the assertion's message, the quickfix list. (Rust keeps unit tests in the file, so there is no file toggle.)
- **rust-analyzer**: expand the macro under the cursor (in a float), open the crate's `Cargo.toml`, explain the error
  code of the line (`rustc --explain E0382`).
- **Debug** (`<leader>rD`): the crate's binary after `cargo build`, or the test under the cursor (its test binary from
  `cargo test --no-run`, run with `--exact`); breakpoints, steps, the panel.
- **Setup** (`<leader>rS`): `rustfmt.toml`, `rust-toolchain.toml` (stable + rustfmt, clippy, rust-src), `clippy.toml`,
  `deny.toml` (cargo-deny: advisories, licenses), a Dockerfile (Debian slim or distroless, dependencies cached) and its
  `.dockerignore`, GitHub Actions (fmt, clippy `-D warnings`, tests, cache), `.editorconfig`, a Makefile preset,
  `.gitignore`.

## Snippets

`testsmodule` (`#[cfg(test)] mod tests` with `use super::*`), `testfunction`, `errorenum` (thiserror), `implblock`,
`tokiomain`, `derive`.

## Pitfalls

- The first rust-analyzer start indexes the crate and its dependencies: the first diagnostics take a moment.
- clippy as the check runs on save; on a very large workspace switch it back with a `.neoconf.json`
  (`"rust-analyzer": { "check": { "command": "check" } }`).
