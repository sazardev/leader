# Rust

Filetype: `rust`.

## Tools

| What | With |
|---|---|
| Treesitter | `rust` |
| LSP / formatter / linter | **none declared** in the registry; formatting and clippy run with `cargo` from the menu |

> For rust-analyzer or format on save, add it in `lua/languages/rust.lua` (`lsp`, `mason`, `formatters`).

## `<leader>r` menu (only in `*.rs`)

The keys are in [`CHEATSHEET.md`](../../CHEATSHEET.md) (generated; not duplicated here).

It runs at the project root (where `Cargo.toml` is) and warns if `cargo` is not installed.
