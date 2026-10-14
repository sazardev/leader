-- Rich Markdown rendering
return {
  "MeanderingProgrammer/render-markdown.nvim",
  ft = "markdown",
  opts = {
    -- Floating windows (LSP hover, signature help) are markdown too: there the plain block of the flat design (ui/flat),
    -- no language heading, no rule line, no sign column — just the signature and its text
    overrides = {
      buftype = {
        nofile = {
          code = { style = "normal", language = false, border = "hide", left_pad = 0, right_pad = 0, sign = false },
          dash = { enabled = false },
          heading = { sign = false },
        },
      },
    },
  },
  config = function(_, opts)
    require("render-markdown").setup(opts)
  end,
}
