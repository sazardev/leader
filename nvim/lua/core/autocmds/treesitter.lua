-- ── Treesitter highlighter startup ───────────────────────────────────────────
-- The "main" branch of nvim-treesitter no longer starts it on its own: without this no
-- capture (@function, @operator...) is highlighted even if the parser is installed.
local M = {}

function M.setup()
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("TreesitterStart", { clear = true }),
    callback = function(args)
      pcall(vim.treesitter.start, args.buf)
    end,
  })
end

return M
