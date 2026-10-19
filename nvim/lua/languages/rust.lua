-- Rust: rust-analyzer with clippy as its check (servers/rust_analyzer.lua), rustfmt on save (from the toolchain:
-- `rustup component add rustfmt`), codelldb for debugging. Menu: cargo, tests in the editor, crates, project setup.
return {
  filetypes = { "rust" },
  treesitter = { "rust", "toml" },
  lsp = { "rust_analyzer" },
  mason = { full = { "rust-analyzer", "codelldb" } },
  formatters = { rust = { "rustfmt" } },
  menu = { name = "Rust", prefix = "r", maps = require "languages.actions.rust", groups = { S = "setup", D = "debug" } },
}
