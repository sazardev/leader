-- XAML (.xaml, WPF/UWP/MAUI/WinUI): XML markup. There is no `xaml` parser in nvim-treesitter, so
-- `vim.treesitter.language.register` maps the `xaml` filetype onto the `xml` parser (see ftdetect/xaml.lua).
-- No LSP: the `xml` treesitter + `prettier` (needs `prettier-plugin-xml` in the project, like Astro needs
-- `prettier-plugin-astro`) + the snippets in `snippets/xaml.json` do the work. Rider's XAML preview has no
-- Neovim equivalent; `dotnet build`/`dotnet format` via <leader>x are the equivalents available here.
return {
  filetypes = { "xaml" },
  treesitter = { "xml" },
  mason = { full = { "prettier" } },
  formatters = { xaml = { "prettier" } },
  menu = {
    name = "XAML",
    prefix = "x",
    maps = require "languages.actions.xaml",
  },
}
