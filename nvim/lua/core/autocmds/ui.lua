-- ── UI settings that some plugin might override ──────────────────────────────
local M = {}

function M.setup()
  -- the hidden cursor of pages that draw their own selection comes back by itself if nothing owns it (utils/cursor.lua)
  require("utils.cursor").setup()
  -- looks for a newer Leader now and then and offers it (lua/update)
  require("update").setup()

  -- Force cmdheight=0 after the full load (overrides any plugin that resets it)
  vim.api.nvim_create_autocmd("VimEnter", {
    group = vim.api.nvim_create_augroup("ForceCmdheight", { clear = true }),
    once = true,
    callback = function()
      vim.o.cmdheight = 0
    end,
  })

  -- NvChad's terminals (<A-i> float, <A-v> vertical, <A-h> horizontal) get the same keys as toggleterm's:
  -- Esc closes the window (the shell keeps running, the same Alt key brings it back), Shift+Esc unfocuses it
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("NvTermEscClose", { clear = true }),
    pattern = { "NvTerm_float", "NvTerm_vsp", "NvTerm_sp" },
    callback = function(ev)
      require("utils.terminal").attach_keys(ev.buf, function()
        vim.api.nvim_win_close(0, true)
      end)
    end,
  })

  -- the start screen (ui/start): at startup with no file, and `:Nvdash`
  require("ui.start").setup()
end

return M
