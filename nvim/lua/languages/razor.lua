-- Razor / Blazor (.razor, .cshtml): HTML + C# in one file. Treesitter `razor` gives highlighting (the
-- `c_sharp`/`html` parsers are the injections inside it); full C# intelligence inside @code blocks needs
-- `seblyng/roslyn.nvim` (co-hosting, the successor of rzls.nvim) — the stock `roslyn_ls` warns it is not
-- supported. The <leader>c menu is the same dotnet one as C# (run, watch with hot reload, build, publish).
-- No formatter on save: `<leader>cF` (`dotnet format`) is the Razor-aware formatter.
return {
  filetypes = { "razor" },
  treesitter = { "razor", "c_sharp", "html" },
  lsp = { "html" },
  formatters = {},
  menu = {
    name = "Razor",
    prefix = "c",
    maps = require "languages.actions.csharp",
    groups = { S = "setup", D = "debug", L = "project", G = "run" },
  },
}
