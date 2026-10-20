return {
  filetypes = { "lua" },
  treesitter = { "lua", "vim", "vimdoc" },
  lsp = { "lua_ls" }, -- the server is chosen in servers/lua.lua (emmylua_ls when installed: ~5x faster across files)
  mason = { full = { "lua-language-server", "emmylua_ls" }, always = { "stylua" } },
  formatters = { lua = { "stylua" } },
}
