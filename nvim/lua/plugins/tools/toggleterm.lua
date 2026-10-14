-- Integrated terminal: used by the per-language menus (utils/terminal.lua) and lazydocker.
-- Position/size: settings.terminal. Colors: those of the active theme (no shading,
-- so the panel uses the editor's exact background, also with the terminal theme).
return {
  "akinsho/toggleterm.nvim",
  cmd = { "ToggleTerm", "TermExec" },
  opts = function()
    local term = require "utils.terminal"
    local scale = require("core.settings").terminal.float_scale
    local flat = require("ui.flat").enabled()
    local function area() -- rows above the statusline
      return vim.o.lines - vim.o.cmdheight - 1
    end
    return {
      size = term.size,
      open_mapping = false,
      direction = term.direction(),
      shade_terminals = false,
      persist_size = false, -- recompute the size on every open
      -- flat: the demo's terminal, a block in the theme's own background over the `deep` editor
      highlights = flat and {
        NormalFloat = { link = "FlatTerm" },
        FloatBorder = { link = "FlatTermBorder" },
      } or nil,
      float_opts = {
        border = require("ui.flat").border(),
        -- flat: the demo's place (5% from each side, 14% from the top, 12% from the bottom); else `float_scale`
        width = function()
          return flat and math.floor(vim.o.columns * 0.9) - 2 or math.floor(vim.o.columns * scale)
        end,
        height = function()
          return flat and math.floor(area() * 0.74) - 2 or math.floor(vim.o.lines * scale)
        end,
        row = flat and function()
          return math.floor(area() * 0.14)
        end or nil,
        col = flat and function()
          return math.floor(vim.o.columns * 0.05)
        end or nil,
      },
      close_on_exit = true,
    }
  end,
  config = function(_, opts)
    require("toggleterm").setup(opts)
    -- Esc in the terminal closes the panel/floating window
    vim.keymap.set("t", "<Esc>", "<cmd>lua require('toggleterm').toggle()<cr>", { desc = "Terminal close (Esc)" })
    -- Esc/Shift+Esc also from the terminal's Normal mode (after a click or Ctrl-\ Ctrl-n the `t` map no longer applies)
    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("TerminalEscClose", { clear = true }),
      pattern = "toggleterm",
      callback = function(ev)
        require("utils.terminal").attach_keys(ev.buf, function()
          require("toggleterm").toggle()
        end)
      end,
    })
    -- Responsive: readjusts the open panels when the window size changes
    vim.api.nvim_create_autocmd("VimResized", {
      group = vim.api.nvim_create_augroup("TerminalResponsive", { clear = true }),
      callback = function()
        require("utils.terminal").refresh()
      end,
    })
  end,
}
