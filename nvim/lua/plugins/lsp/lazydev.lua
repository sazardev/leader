-- Types and completion for the Neovim API and plugins when editing Lua (lua_ls).
-- Only loads on .lua files; adds to lua_ls only the libraries the code uses.
return {
  "folke/lazydev.nvim",
  ft = "lua",
  opts = {
    library = {
      { path = "${3rd}/luv/library", words = { "vim%.uv" } },
    },
  },
}
