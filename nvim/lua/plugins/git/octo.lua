-- GitHub PRs, issues, discussions and reviews inside Neovim, on top of the gh CLI (the `<leader>Gh` menu).
-- Lazy: nothing loads until `:Octo` (or one of the menu entries) runs. Telescope is the picker this config already
-- has; plenary and nvim-web-devicons are already installed for other plugins.
return {
  "pwntester/octo.nvim",
  cmd = "Octo",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim",
    "nvim-tree/nvim-web-devicons",
  },
  opts = {
    picker = "telescope",
    enable_builtin = true, -- bare `:Octo` lists every action
  },
}
