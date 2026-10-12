-- Añadir/quitar/cambiar delimitadores: sa / sd / sr
return {
  "echasnovski/mini.surround",
  keys = {
    { "sa", mode = { "n", "x" }, desc = "Surround add" },
    { "sd", mode = "n", desc = "Surround delete" },
    { "sr", mode = "n", desc = "Surround replace" },
  },
  opts = {
    mappings = {
      add = "sa",
      delete = "sd",
      find = "sf",
      find_left = "sF",
      highlight = "sh",
      replace = "sr",
      update_n_lines = "sn",
    },
  },
  config = function(_, opts)
    require("mini.surround").setup(opts)
  end,
}
