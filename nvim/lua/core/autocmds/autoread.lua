-- ── Reload files changed outside nvim ────────────────────────────────────────
-- `autoread` only acts when :checktime is called; nvim does not do it when focus
-- returns in a terminal. This way whatever git, formatters or another editor change
-- is reloaded automatically (buffers with unsaved changes are never overwritten: nvim asks).
local M = {}

function M.setup()
  vim.api.nvim_create_autocmd({ "FocusGained", "TermClose", "TermLeave" }, {
    group = vim.api.nvim_create_augroup("AutoRead", { clear = true }),
    callback = function()
      -- in the command-line window checktime would error
      if vim.o.autoread and vim.fn.getcmdwintype() == "" then
        vim.cmd.checktime()
      end
    end,
  })
end

return M
