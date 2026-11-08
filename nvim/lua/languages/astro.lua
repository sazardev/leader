-- Formatting requires prettier-plugin-astro in the project (or global).
return {
  filetypes = { "astro" },
  treesitter = { "astro" },
  lsp = { "astro" },
  mason = { full = { "astro-language-server", "prettier" } },
  formatters = { astro = { "prettier" } },
  menu = { name = "Astro", prefix = "o", maps = require "languages.actions.astro", groups = { S = "setup" } },
}
