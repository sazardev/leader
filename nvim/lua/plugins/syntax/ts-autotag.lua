-- Auto-close and rename of JSX/HTML tags
return {
  "windwp/nvim-ts-autotag",
  event = { "BufReadPre", "BufNewFile" },
  opts = {},
  config = function(_, opts)
    require("nvim-ts-autotag").setup(opts)
  end,
}
