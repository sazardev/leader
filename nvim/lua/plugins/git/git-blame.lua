-- Inline blame: disabled by default, toggled with <leader>Gb (no overhead on BufRead)
return {
  "f-person/git-blame.nvim",
  cmd = "GitBlameToggle",
  opts = {
    date_format = "%Y-%m-%d %H:%M",
    virtual_text_column = 80,
    enabled = false,
  },
  config = function(_, opts)
    require("gitblame").setup(opts)
  end,
}
