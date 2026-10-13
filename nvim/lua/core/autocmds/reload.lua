-- ── Config auto-reload after `git pull` ──────────────────────────────────────
-- The .githooks/post-merge hook creates a marker in stdpath("data"); when the
-- UI is entered init.lua is reloaded and the marker is deleted.
local M = {}

function M.setup()
  local marker = vim.fn.stdpath "data" .. "/.config-reloaded"

  vim.api.nvim_create_autocmd("UIEnter", {
    group = vim.api.nvim_create_augroup("ConfigAutoReload", { clear = true }),
    once = true,
    callback = function()
      if vim.fn.filereadable(marker) ~= 1 then
        return
      end
      vim.cmd "silent! luafile $MYVIMRC"
      vim.fn.delete(marker)
      vim.notify "Config reloaded automatically after git pull"
    end,
  })
end

return M
