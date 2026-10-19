-- Swift (Swift Package Manager): sourcekit-lsp and `swift format` come with the toolchain (nothing to download); the
-- server is only enabled when the toolchain is there. swiftlint lints when it is installed. Menu <leader>i: build,
-- run, tests in the editor, packages, project setup.
return {
  filetypes = { "swift" },
  treesitter = { "swift" },
  lsp = vim.fn.executable "sourcekit-lsp" == 1 and { "sourcekit" } or {},
  formatters = { swift = { "swift" } },
  linters = { swift = { "swiftlint" } },
  menu = {
    name = "Swift",
    prefix = "i",
    maps = require "languages.actions.swift",
    groups = { S = "setup", D = "debug" },
  },
}
