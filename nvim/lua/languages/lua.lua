return {
  filetypes = { "lua" },
  treesitter = { "lua", "vim", "vimdoc" },
  lsp = { "lua_ls" }, -- NvChad already enables it; it is declared here
  mason = { full = { "lua-language-server" }, always = { "stylua" } },
  formatters = { lua = { "stylua" } },
}
