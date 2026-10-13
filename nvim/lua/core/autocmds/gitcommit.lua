-- ── Commit buffer settings ───────────────────────────────────────────────────
-- For `git commit` (COMMIT_EDITMSG) and for the commit panel (commit/panel.lua):
-- spelling and guides at the Conventional Commits columns (subject ≤ 72, body ≤ 72).
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
