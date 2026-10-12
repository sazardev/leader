-- Terminal integrada: la usan los menús por lenguaje (utils/terminal.lua) y lazydocker.
-- Posición/tamaño: settings.terminal. Colores: los del tema activo (sin sombreado,
-- así el panel usa el fondo exacto del editor, también con el tema de la terminal).
return {
  "akinsho/toggleterm.nvim",
  cmd = { "ToggleTerm", "TermExec" },
  opts = function()
    local term = require "utils.terminal"
    local scale = require("core.settings").terminal.float_scale
    return {
      size = term.size,
      open_mapping = false,
      direction = term.direction(),
      shade_terminals = false,
      persist_size = false, -- recalcular el tamaño en cada apertura
      float_opts = {
        border = "single",
        width = function()
          return math.floor(vim.o.columns * scale)
        end,
        height = function()
          return math.floor(vim.o.lines * scale)
        end,
      },
      close_on_exit = true,
    }
  end,
  config = function(_, opts)
    require("toggleterm").setup(opts)
    -- Esc en terminal cierra el panel/ventana flotante
    vim.keymap.set("t", "<Esc>", "<cmd>lua require('toggleterm').toggle()<cr>", { desc = "Terminal close (Esc)" })
    -- Responsivo: reajusta los paneles abiertos al cambiar el tamaño de la ventana
    vim.api.nvim_create_autocmd("VimResized", {
      group = vim.api.nvim_create_augroup("TerminalResponsive", { clear = true }),
      callback = function()
        require("utils.terminal").refresh()
      end,
    })
  end,
}
