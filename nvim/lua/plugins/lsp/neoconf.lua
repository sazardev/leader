-- Per-project LSP config (.neoconf.json)
return {
  "folke/neoconf.nvim",
  event = "BufReadPre",
  opts = {},
  config = function(_, opts)
    require("neoconf").setup(opts)
  end,
}
