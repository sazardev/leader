-- Panel de diagnósticos
return {
  "folke/trouble.nvim",
  cmd = "Trouble",
  keys = {
    { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics project list (Trouble)" },
  },
  opts = {},
  config = function(_, opts)
    require("trouble").setup(opts)
  end,
}
