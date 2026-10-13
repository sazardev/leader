-- No formatter in conform: prismals formats it via LSP (lsp_format = "fallback").
return {
  filetypes = { "prisma" },
  treesitter = { "prisma" },
  lsp = { "prismals" },
  mason = { full = { "prisma-language-server" } },
}
