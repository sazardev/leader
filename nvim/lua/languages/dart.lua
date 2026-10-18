-- The LSP (dartls) is managed by flutter-tools.nvim, not vim.lsp.enable.
return {
  filetypes = { "dart" },
  treesitter = { "dart" },
  formatters = { dart = { "dart_format" } },
  menu = { name = "Dart / Flutter", prefix = "d", maps = require "languages.actions.dart", groups = { z = "Fold" } },
}
