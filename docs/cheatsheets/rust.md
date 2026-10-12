# Rust

Filetype: `rust`.

## Herramientas

| Qué | Con |
|---|---|
| Treesitter | `rust` |
| LSP / formatter / linter | **no hay declarados** en el registro; el formato y clippy corren con `cargo` desde el menú |

> Para rust-analyzer o formato al guardar, añádelo en `lua/languages/rust.lua` (`lsp`, `mason`, `formatters`).

## Menú `<leader>r` (solo en `*.rs`)

Las teclas están en [`CHEATSHEET.md`](../../CHEATSHEET.md) (generado; no se duplican aquí).

Corre en la raíz del proyecto (donde está `Cargo.toml`) y avisa si `cargo` no está instalado.
