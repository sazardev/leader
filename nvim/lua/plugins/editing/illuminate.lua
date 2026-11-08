-- Highlights all occurrences of the word under the cursor
return {
  "RRethy/vim-illuminate",
  event = { "CursorHold", "CursorHoldI" },
  opts = {
    delay = 200,
    filetypes_denylist = { "NvimTree", "TelescopePrompt", "alpha", "dashboard", "lazy", "mason", "nvdash" },
    -- locked reading mode (*.md/*.mdx): no word highlight following the cursor, even if the plugin loads after the mode started
    should_enable = function(bufnr)
      return not (bufnr and vim.api.nvim_buf_is_valid(bufnr) and vim.b[bufnr].reading_locked)
    end,
  },
  config = function(_, opts)
    require("illuminate").configure(opts)
  end,
}
