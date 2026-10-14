return {
  "mason-org/mason.nvim",
  opts = { ui = { border = require("ui.flat").border() } }, -- flat (ui/flat)
  config = function(_, opts)
    require("mason").setup(opts)
  end,
}
