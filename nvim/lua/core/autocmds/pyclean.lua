-- Conservative Python import cleanup before saving (see settings.python.clean.on_save).
local M = {}

function M.setup()
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = vim.api.nvim_create_augroup("leader_pyclean", { clear = true }),
    pattern = "*.py",
    callback = function(args)
      if vim.bo[args.buf].filetype == "python" then
        require("pyclean").on_save(args.buf)
      end
    end,
  })
end

return M
