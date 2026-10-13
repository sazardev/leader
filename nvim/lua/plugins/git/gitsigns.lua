return {
  "lewis6991/gitsigns.nvim",
  opts = {
    -- Git = thin bar next to the number (drawn by the statuscolumn in one cell, see core/settings.lua) (┃ added/changed, ▁▔ deleted, ┆ untracked). The line NUMBER
    -- belongs to diagnostics (utils/diagblocks.lua), so it is not tinted here
    signcolumn = true,
    numhl = false,
    linehl = false, -- no highlight on the whole line
    current_line_blame = false,
    update_debounce = 100, -- debounce = fewer redraws
  },
  config = function(_, opts)
    require("gitsigns").setup(opts)
  end,
}
