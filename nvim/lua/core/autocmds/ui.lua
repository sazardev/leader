-- ── UI settings that some plugin might override ──────────────────────────────
local M = {}

function M.setup()
  -- Force cmdheight=0 after the full load (overrides any plugin that resets it)
  vim.api.nvim_create_autocmd("VimEnter", {
    group = vim.api.nvim_create_augroup("ForceCmdheight", { clear = true }),
    once = true,
    callback = function()
      vim.o.cmdheight = 0
    end,
  })

  -- The dashboard (nvdash) is redrawn on resize setting `modifiable = true` and
  -- never locks it again (NvChad bug): text could be typed into it. It is
  -- re-locked right after its redraw.
  vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = vim.api.nvim_create_augroup("RelockNvdash", { clear = true }),
    callback = function()
      vim.schedule(function()
        local buf = vim.g.nvdash_buf
        if buf and vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "nvdash" then
          vim.bo[buf].modifiable = false
        end
      end)
    end,
  })
end

return M
