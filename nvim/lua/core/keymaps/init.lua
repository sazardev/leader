-- ── Keymaps: order matters (NvChad first, then cleanup, then ours) ───────────
local M = {}

function M.setup()
  require "nvchad.mappings"
  require("core.keymaps.cleanup").setup()
  require("core.keymaps.general").setup()
  require("menus").setup()
  -- after the menus: they load which-key, and lazy then deletes the stub NvChad's spec put on `c` (lazy-load key),
  -- which would take our `c` with it
  require("history").setup()
end

return M
