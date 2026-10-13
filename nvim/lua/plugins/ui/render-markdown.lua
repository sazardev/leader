-- Rich Markdown rendering
return {
  "MeanderingProgrammer/render-markdown.nvim",
  ft = "markdown",
  opts = {},
  config = function(_, opts)
    require("render-markdown").setup(opts)
  end,
}
