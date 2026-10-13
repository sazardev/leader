-- ── Keymaps: order matters (NvChad first, then cleanup, then ours) ───────────
local M = {}

function M.setup()
  require "nvchad.mappings"
  require("core.keymaps.cleanup").setup()
  require("core.keymaps.general").setup()
  require("menus").setup()
end

return M
