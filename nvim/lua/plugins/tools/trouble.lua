-- Diagnostics panel
return {
  "folke/trouble.nvim",
  cmd = "Trouble",
  keys = {
    { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics project list (Trouble)" },
  },
  opts = {
    modes = {
      -- focus: on opening, the cursor enters the panel (by default it stays in the code and you
      -- cannot select or press Enter)
      diagnostics = { focus = true },
    },
    keys = {
      -- Enter jumps to the diagnostic and opens its popup, like <leader>xd
      ["<cr>"] = {
        action = function(view, ctx)
          if not ctx.item then
            return view:fold(ctx.node) -- on a file: folds/unfolds
          end
          view:jump(ctx.item)
          vim.schedule(require("utils.diagblocks").popup)
        end,
        desc = "Jump and show diagnostic popup",
      },
    },
  },
  config = function(_, opts)
    require("trouble").setup(opts)
  end,
}
