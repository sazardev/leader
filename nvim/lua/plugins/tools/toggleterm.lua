-- Integrated terminal: used by the per-language menus (utils/terminal.lua) and lazydocker.
-- Position/size: settings.terminal. Colors: those of the active theme (no shading,
-- so the panel uses the editor's exact background, also with the terminal theme).
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
      persist_size = false, -- recompute the size on every open
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
    -- Esc in the terminal closes the panel/floating window
    vim.keymap.set("t", "<Esc>", "<cmd>lua require('toggleterm').toggle()<cr>", { desc = "Terminal close (Esc)" })
    -- Responsive: readjusts the open panels when the window size changes
    vim.api.nvim_create_autocmd("VimResized", {
      group = vim.api.nvim_create_augroup("TerminalResponsive", { clear = true }),
      callback = function()
        require("utils.terminal").refresh()
      end,
    })
  end,
}
