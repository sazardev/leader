return {
  "lewis6991/gitsigns.nvim",
  opts = {
    -- Git = barra fina en la signcolumn (┃ añadido/cambiado, ▁▔ borrado, ┆ sin seguir). El NÚMERO de línea
    -- es de los diagnósticos (utils/diagblocks.lua), así que aquí no se tiñe
    signcolumn = true,
    numhl = false,
    linehl = false, -- sin highlight en la línea entera
    current_line_blame = false,
    update_debounce = 100, -- debounce = menos redraws
  },
  config = function(_, opts)
    require("gitsigns").setup(opts)
  end,
}
