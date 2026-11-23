-- Auto-import the standard library/data-science aliases as they are typed in Python.
-- The work itself lives in utils/pyauto.lua; this file only wires the event.
local M = {}

function M.setup()
  vim.api.nvim_create_autocmd("TextChangedI", {
    group = vim.api.nvim_create_augroup("leader_pyimports", { clear = true }),
    pattern = { "*.py", "*.pyi" },
    callback = function(args)
      require("utils.pyauto").ensure(args.buf)
    end,
  })
end

return M
