-- ── Ajustes del buffer de commit ─────────────────────────────────────────────
-- Para `git commit` (COMMIT_EDITMSG) y para la ventana de mensaje de utils/commit.lua:
-- ortografía y guías en las columnas de Conventional Commits (asunto ≤ 72, cuerpo ≤ 72).
local M = {}

function M.setup()
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("GitCommitBuffer", { clear = true }),
    pattern = "gitcommit",
    callback = function(args)
      local max = require("core.settings").git.commit.subject_max
      vim.bo[args.buf].textwidth = max
      vim.wo.spell = true
      vim.wo.colorcolumn = tostring(max + 1)
    end,
  })
end

return M
