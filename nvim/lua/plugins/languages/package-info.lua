-- npm package versions inside package.json
return {
  "vuki656/package-info.nvim",
  ft = "json",
  opts = {},
  config = function(_, opts)
    require("package-info").setup(opts)
  end,
}
