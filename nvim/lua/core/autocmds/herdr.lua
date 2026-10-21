-- ── Herdr: this nvim inside the workspace ─────────────────────────────────────
-- Inside a Herdr pane, nvim registers itself as an agent (so Herdr knows it is there, can bring it back after the
-- server restarts and shows what it is doing) and reports what the inline agent is doing. Outside Herdr, or when the
-- user turned it off, nothing happens.
local herdr = require "herdr"

local M = {}

function M.setup()
  if not herdr.enabled() then
    return
  end
  local group = vim.api.nvim_create_augroup("Herdr", { clear = true })

  -- the command Herdr runs to bring this pane back
  vim.api.nvim_create_user_command("HerdrResume", function()
    herdr.resume()
  end, { desc = "Restore the folder's session (Herdr resume command)" })

  if not herdr.inside() then
    return
  end

  if herdr.register_mode() ~= "off" then
    vim.api.nvim_create_autocmd("VimEnter", {
      group = group,
      callback = function()
        herdr.register()
      end,
    })
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = group,
      callback = function()
        herdr.release()
      end,
    })
  end

  -- what the inline agent is doing, told to herdr
  require("herdr.report").setup()
end

return M
