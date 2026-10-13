return {
  filetypes = { "go", "gomod", "gowork" },
  treesitter = { "go", "gomod", "gosum", "gowork" },
  lsp = { "gopls" },
  mason = {
    always = { "goimports", "gofumpt" },
    full = { "gopls", "golangci-lint" },
  },
  formatters = { go = { "goimports", "gofumpt" } }, -- imports first, then strict formatting
  linters = { go = { "golangcilint" } },
  linters_light = { go = { "govet" } }, -- go vet is ephemeral; golangci-lint is heavy

  -- nvim-lint does not ship "govet" out of the box (only "golangcilint"); go vet already comes
  -- with the toolchain, zero extra installation.
  setup_lint = function(lint)
    lint.linters.govet = {
      cmd = "go",
      args = { "vet", "./..." },
      stdin = false,
      ignore_exitcode = true,
      append_fname = false,
      stream = "stderr",
      parser = require("lint.parser").from_errorformat("%f:%l:%c: %m", { source = "govet" }),
    }
  end,

  menu = { name = "Go", prefix = "g", maps = require "languages.actions.go" },
}
