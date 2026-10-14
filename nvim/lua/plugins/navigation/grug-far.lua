-- Reemplazo global estilo VS Code
return {
  "MagicDuck/grug-far.nvim",
  cmd = "GrugFar",
  keys = {
    { "<leader>fr", "<cmd>GrugFar<cr>", desc = "Find replace in project" },
  },
  opts = {
    icons = { enabled = false }, -- plain labels (Search:, Replace:), like the rest of the flat UI
    keymaps = {
      close = { n = "q" },
    },
  },
  config = function(_, opts)
    require("grug-far").setup(opts)
  end,
}
