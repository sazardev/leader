-- LSP servers: list in lua/languages/, overrides in lua/servers/.
return {
  "neovim/nvim-lspconfig",
  dependencies = { "saghen/blink.cmp" },
  config = function()
    require("servers").setup()
  end,
}
