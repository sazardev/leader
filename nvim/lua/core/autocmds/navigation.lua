-- ── History of files visited in the session (<leader>H) ──────────────────────
local M = {}

function M.setup()
  local nav = require "utils.navigation"
  local group = vim.api.nvim_create_augroup("NavigationHistory", { clear = true })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(args)
      nav.track(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd("BufLeave", {
    group = group,
    callback = function(args)
      nav.save_position(args.buf)
    end,
  })
end

return M
