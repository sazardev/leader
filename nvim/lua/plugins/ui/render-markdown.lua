-- Rich Markdown rendering
return {
  "MeanderingProgrammer/render-markdown.nvim",
  ft = "markdown",
  opts = {
    -- Plain source by default: no conceal, files open editable. Toggle per
    -- buffer with <leader>mr (`RenderMarkdown toggle`). The agent chat and
    -- history preview still render on demand via the API (`force = true`).
    enabled = false,
    -- Floating windows (LSP hover, signature help) are markdown too: there the plain block of the flat design (ui/flat),
    -- no language heading, no rule line, no sign column — just the signature and its text
    overrides = {
      buftype = {
        nofile = {
          -- read-only views (hover, agent answers, the agent history preview): rendered in every mode, also while a
          -- picker keeps you in insert mode in its prompt
          render_modes = true,
          code = { style = "normal", language = false, border = "hide", left_pad = 0, right_pad = 0, sign = false },
          dash = { enabled = false },
          heading = { sign = false },
        },
      },
    },
  },
  config = function(_, opts)
    if require("ui.flat").enabled() then
      -- flat: tables are aligned columns, never a drawn box (no top/bottom rules, the separators are air)
      opts.pipe_table = {
        style = "normal",
        border = { " ", " ", " ", " ", " ", " ", " ", " ", " ", " ", " " },
        alignment_indicator = " ",
      }
      -- headings and checkboxes in plain Unicode, not Nerd Font glyphs (the landing page's demo draws the same ones): the
      -- flat design needs no patched font
      opts.heading = { icons = { "▣ ", "◎ ", "◎ ", "◎ ", "◎ ", "◎ " } }
      opts.checkbox = {
        unchecked = { icon = "☐ " },
        checked = { icon = "☑ " },
      }
    end
    require("render-markdown").setup(opts)
  end,
}
