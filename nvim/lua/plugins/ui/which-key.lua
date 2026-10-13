-- Keymaps popup. The per-language/git menus are buffer-local (lua/menus/).
return {
  "folke/which-key.nvim",
  config = function()
    require("which-key").setup {
      delay = 0,
      icons = {
        mappings = false,
      },
      spec = {
        { "<leader>f", group = "Find" },
        { "<leader>x", group = "Diagnostics" },
        { "<leader>h", group = "Harpoon" },
        { "<leader>n", group = "Nvim-tree folders" },

        -- NvChad prefixes we do not want to see in the popup
        { "<leader>v", hidden = true },
        { "<leader>wK", hidden = true },
        { "<leader>wk", hidden = true },
        { "<leader>c", hidden = true },
        { "<leader>o", hidden = true },
        { "<leader>b", hidden = true },

        -- Disabled keymaps inside visible groups
        { "<leader>fa", hidden = true },
        { "<leader>fz", hidden = true },
        { "<leader>fh", hidden = true },
        { "<leader>fc", hidden = true },
        { "<leader>xb", hidden = true },
      },
    }
  end,
}
