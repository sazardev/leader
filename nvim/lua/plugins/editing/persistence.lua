-- Sessions per folder (and git branch): saves buffers and windows on exit.
-- They are restored on demand (dashboard button, <leader>P): see utils/session.lua.
return {
  "folke/persistence.nvim",
  event = "BufReadPre",
  opts = {},
  config = function(_, opts)
    require("persistence").setup(opts)

    -- No UI = a script, a test or a headless run: it must never write a session. Persistence saves one on every exit, and
    -- a test that opens temp files in the repo's folder would replace the real session of that folder with files that no
    -- longer exist (the next restore of the project opens an empty buffer). The terminal and the desktop app always have
    -- a UI attached when this loads.
    if #vim.api.nvim_list_uis() == 0 then
      require("persistence").stop()
    end

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
