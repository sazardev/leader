return {
  filetypes = { "json" },
  treesitter = { "json" },
  lsp = { "jsonls" }, -- schemas via SchemaStore (see servers/jsonls.lua)
  mason = { full = { "prettier", "json-lsp", "jsonlint" } },
  formatters = { json = { "prettier" } },
  linters = { json = { "jsonlint" } },
}
