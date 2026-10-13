-- Highlights all occurrences of the word under the cursor
return {
  "RRethy/vim-illuminate",
  event = { "CursorHold", "CursorHoldI" },
  opts = {
    delay = 200,
    filetypes_denylist = { "NvimTree", "TelescopePrompt", "alpha", "dashboard", "lazy", "mason", "nvdash" },
  },
  config = function(_, opts)
    require("illuminate").configure(opts)
  end,
}
