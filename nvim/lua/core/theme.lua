-- ── Loading the base46 cache (NvChad theme) ──────────────────────────────────
local M = {}

function M.load()
  -- If the active theme is the terminal one and Alacritty changed, recompile before reading the cache
  require("appearance").sync()

  for _, name in ipairs { "defaults", "statusline" } do
    dofile(vim.g.base46_cache .. name)
  end
end

return M
