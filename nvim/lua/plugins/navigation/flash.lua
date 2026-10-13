-- Quick jump with s/S (does not overwrite r/R)
return {
  "folke/flash.nvim",
  event = "VeryLazy",
  keys = {
    {
      "s",
      function()
        require("flash").jump()
      end,
      mode = { "n", "x", "o" },
      desc = "Flash jump",
    },
    {
      "S",
      function()
        require("flash").treesitter()
      end,
      mode = { "n", "x", "o" },
      desc = "Flash treesitter",
    },
  },
  opts = {
    modes = {
      char = { enabled = false },
    },
  },
  config = function(_, opts)
    require("flash").setup(opts)
  end,
}
