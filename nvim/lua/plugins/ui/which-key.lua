-- Keymaps popup. The per-language/git menus are buffer-local (lua/menus/).
return {
  "folke/which-key.nvim",
  config = function()
    require("which-key").setup {
      delay = 0,
      -- flat bottom panel: air around the content, `key ➜ description`, `+Group` (see ui/flat)
      win = { border = "none", padding = { 1, 2 }, title = true, title_pos = "left" },
      layout = { width = { min = 22, max = 26 }, spacing = 4 }, -- columns of the same width, long labels cut: like the demo's grid
      icons = {
        mappings = false,
        separator = "➜",
        group = "+",
        breadcrumb = "»",
        -- keys as words (Space, Esc, BS), like the demo: no Nerd Font glyphs in the footer
        keys = {
          Up = "↑ ",
          Down = "↓ ",
          Left = "← ",
          Right = "→ ",
          C = "Ctrl+",
          M = "Alt+",
          D = "Cmd+",
          S = "Shift+",
          CR = "Enter ",
          NL = "Enter ",
          Esc = "Esc ",
          BS = "BS ",
          Space = "Space ",
          Tab = "Tab ",
          ScrollWheelDown = "Scroll↓ ",
          ScrollWheelUp = "Scroll↑ ",
        },
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
    require("ui.flat.labels").install() -- "Go run" inside Go reads "run"
  end,
}
