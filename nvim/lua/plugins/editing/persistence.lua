-- Sessions per folder (and git branch): saves buffers and windows on exit.
-- They are restored on demand (dashboard button, <leader>P): see utils/session.lua.
return {
  "folke/persistence.nvim",
  event = "BufReadPre",
  opts = {},
  config = function(_, opts)
    require("persistence").setup(opts)

    -- Before saving, auxiliary windows (tree, outline, terminal...) are closed:
    -- a session cannot rebuild them and would restore them as empty windows.
    vim.api.nvim_create_autocmd("User", {
      group = vim.api.nvim_create_augroup("PersistenceCleanup", { clear = true }),
      pattern = "PersistenceSavePre",
      callback = function()
        require("utils.session").close_auxiliary()
      end,
    })
  end,
}
