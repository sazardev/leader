-- Statusline (replaces NvChad's). The theme comes from base46: ui/lualine/theme.lua
local components = require "ui.lualine.components"

return {
  "nvim-lualine/lualine.nvim",
  event = "VeryLazy",
  opts = {
    options = {
      theme = "auto", -- resolved in config() by reading base46
      section_separators = "",
      component_separators = "",
      globalstatus = true,
      refresh = {
        statusline = 200,
        winbar = 200,
        tabline = 200,
        underline = 1000,
      },
    },
    sections = {
      -- the mode and position chips keep a fixed width, the text centered (the demo's 76px / 64px chips)
      lualine_a = { { "mode", fmt = components.centered(8) } },
      lualine_b = { "filename" },
      lualine_c = { { "branch", icon = "⎇" } },
      lualine_x = {
        components.agent_status(),
        components.flutter_status(),
        components.dartgen_status(),
        components.darttest_status(),
        components.diagnostic_count(vim.diagnostic.severity.ERROR),
        components.diagnostic_count(vim.diagnostic.severity.WARN),
      },
      lualine_y = {
        { components.project_name, cond = components.is_wide },
      },
      lualine_z = { { components.position, fmt = components.centered(6) } },
    },
    inactive_sections = {
      lualine_a = {},
      lualine_b = { "filename" },
      lualine_c = {},
      lualine_x = { "filetype" },
      lualine_y = {},
      lualine_z = { "location" },
    },
  },
  config = function(_, opts)
    local theme = require "ui.lualine.theme"

    opts.options.theme = theme.build()
    require("lualine").setup(opts)

    -- Re-applies the theme when NvChad reloads colors (theme_toggle, <leader>S...)
    local function retheme()
      local ok, lualine = pcall(require, "lualine")
      if ok then
        opts.options.theme = theme.build()
        lualine.setup(opts) -- full config: a partial setup would lose the sections
      end
    end

    local group = vim.api.nvim_create_augroup("LualineNvChadTheme", { clear = true })
    vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = retheme })
    vim.api.nvim_create_autocmd("User", { group = group, pattern = "NvThemeReload", callback = retheme })
  end,
}
