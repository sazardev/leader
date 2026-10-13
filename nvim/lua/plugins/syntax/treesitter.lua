-- Parsers declared in lua/languages/ (`treesitter` field).
return {
  "nvim-treesitter/nvim-treesitter",
  opts = {
    ensure_installed = require("languages").treesitter(),
  },
  config = function(_, opts)
    -- The new nvim-treesitter API ("main" branch) NO longer installs by itself the
    -- parsers listed in ensure_installed inside .setup(): you must request it
    -- explicitly with .install(). It also requires the `tree-sitter` binary
    -- (`tree-sitter-cli` package) on the system, not just a C compiler.
    require("nvim-treesitter").setup {}
    require("nvim-treesitter").install(opts.ensure_installed)
  end,
}
