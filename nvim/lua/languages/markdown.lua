-- MDX (*.mdx) is detected as `markdown` (ftdetect/mdx.lua): same rendering, formatting, linting and menu.
-- There is no `mdx` treesitter parser in nvim-treesitter; JSX stays visible as html and imports/expressions as text.
return {
  filetypes = { "markdown" },
  treesitter = { "markdown" },
  mason = { full = { "markdownlint-cli2", "markdownlint", "prettier" } },
  -- markdownlint-cli2 fixes rules; prettier formats
  formatters = { markdown = { "markdownlint-cli2", "prettier" } },
  linters = { markdown = { "markdownlint" } },
  menu = { name = "Markdown", prefix = "m", maps = require "languages.actions.markdown" },
}
