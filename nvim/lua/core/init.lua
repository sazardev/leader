-- ── Orchestrator: load order of the base configuration ───────────────────────
-- Each responsibility lives in its own module; here only the order is decided.
local M = {}

function M.setup()
  require("core.theme").load()
  require("core.options").setup()
  require("ui.flat").setup()
  require("core.clipboard").setup()
  require("core.bigfile").setup()
  require("core.preload").setup()
  require("gui").setup() -- only inside the desktop app (app/)
  require("core.autocmds").setup()

  -- NvChad loads its keymaps with vim.schedule: do the same so that user
  -- mappings override theirs.
  vim.schedule(function()
    require("core.keymaps").setup()
  end)
end

return M
