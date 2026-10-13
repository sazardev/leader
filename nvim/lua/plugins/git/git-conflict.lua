-- Resolve merge conflicts (ours/theirs/both/none) without editing the markers.
-- The shortcuts live in the <leader>G menu (menus/git.lua): the default ones (`co`, `cb`...)
-- would override nvim's `c` operators.
return {
  "akinsho/git-conflict.nvim",
  version = "*",
  event = "BufReadPost",
  opts = {
    default_mappings = false,
  },
}
