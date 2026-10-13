-- Panel de diagnósticos
return {
  "folke/trouble.nvim",
  cmd = "Trouble",
  keys = {
    { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics project list (Trouble)" },
  },
  opts = {
    modes = {
      -- focus: al abrirlo el cursor entra al panel (por defecto se queda en el código y no se
      -- puede elegir ni dar Enter)
      diagnostics = { focus = true },
    },
    keys = {
      -- Enter salta al diagnóstico y abre su popup, igual que <leader>xd
      ["<cr>"] = {
        action = function(view, ctx)
          if not ctx.item then
            return view:fold(ctx.node) -- sobre un archivo: pliega/despliega
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
