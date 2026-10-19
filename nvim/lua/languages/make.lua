-- Make: treesitter and checkmake. The targets themselves are run from <leader>R (lua/tasks/), with presets per
-- language; Neovim's own ftplugin keeps real tabs in Makefiles.
return {
  filetypes = { "make" },
  treesitter = { "make" },
  mason = { full = { "checkmake" } },
  linters = { make = { "checkmake" } },
}
