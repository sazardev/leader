-- Highlights TODO / FIXME / HACK and searches for them with ripgrep
return {
  "folke/todo-comments.nvim",
  event = "BufReadPost",
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = {
    signs = true,
    signs_priority = 8,
    keywords = {
      FIX = { icon = "!", color = "error", alt = { "FIXME", "BUG", "FIXIT", "ISSUE" } },
      TODO = { icon = "T", color = "info" },
      HACK = { icon = "H", color = "warning" },
      WARN = { icon = "W", color = "warning", alt = { "WARNING", "XXX" } },
      PERF = { icon = "P", color = "default", alt = { "OPTIM", "PERFORMANCE", "OPTIMIZE" } },
      NOTE = { icon = "N", color = "hint", alt = { "INFO" } },
      TEST = { icon = "X", color = "error", alt = { "TESTING", "PASSED", "FAILED" } },
    },
    gui_style = { fg = "NONE", bg = "NONE", bold = true },
    merge_keywords = true,
    highlight = { multiline = true, multiline_pattern = "^.", multiline_context = 10 },
    search = { command = "rg", pattern = [[\b(KEYWORDS):]] },
  },
  config = function(_, opts)
    require("todo-comments").setup(opts)
  end,
}
