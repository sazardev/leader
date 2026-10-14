-- Telescope: respects .gitignore in searches, no icons in results.
local no_icons = require("utils.telescope").no_icons

-- Directories we never want in find_files
local EXCLUDED = { ".git", "node_modules", ".next", "dist", "build", "vendor", "target", ".cache", ".nuxt", "coverage" }

local function find_command()
  local cmd = { "rg", "--files", "--hidden", "--no-ignore" }
  for _, dir in ipairs(EXCLUDED) do
    vim.list_extend(cmd, { "--glob", "!" .. dir })
  end
  return cmd
end

return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    {
      "nvim-telescope/telescope-fzf-native.nvim",
      build = "cmake -S. -Bbuild -DCMAKE_BUILD_TYPE=Release && cmake --build build --config Release",
      enabled = vim.fn.executable "cmake" == 1,
    },
  },
  opts = {
    defaults = {
      path_display = { "truncate" },
      -- flat: one cell of air before the text; the selection is a solid row across the whole block
      prompt_prefix = " > ",
      selection_caret = " ",
      entry_prefix = " ",
      -- the preview's path line (ui/flat/telescope.lua) shows the file being previewed
      dynamic_preview_title = true,
      -- flat: results above, the prompt right under them, preview on the right (ui/flat/telescope.lua draws the
      -- blocks; the layout below is the fallback with `settings.ui.flat = false`). Best match sits next to the prompt.
      sorting_strategy = "descending",
      border = true,
      borderchars = { " ", " ", " ", " ", " ", " ", " ", " " },
      results_title = "Results",
      -- The preview is hidden when the window is narrow (preview_cutoff, default
      -- 120 columns / 40 lines): it is kept always visible and, if it does not fit alongside
      -- (fewer than flip_columns), it goes BELOW the list instead of disappearing.
      layout_strategy = "flex",
      layout_config = {
        prompt_position = "bottom",
        width = 0.9,
        height = 0.9,
        flex = { flip_columns = 110 },
        horizontal = { prompt_position = "bottom", preview_cutoff = 0, preview_width = 0.55 },
        vertical = { prompt_position = "bottom", preview_cutoff = 0, preview_height = 0.5, mirror = true },
      },
    },
    pickers = {
      find_files = {
        hidden = true,
        entry_maker = no_icons(),
        find_command = find_command(),
      },
      -- grep rows read `path:line:col: text`, without file icons (like the demo's)
      live_grep = { disable_devicons = true },
      grep_string = { disable_devicons = true },
      buffers = { entry_maker = no_icons() },
      oldfiles = { entry_maker = no_icons() },
    },
  },
  config = function(_, opts)
    local flat = require "ui.flat"
    if flat.enabled() then
      opts.defaults.create_layout = require("ui.flat.telescope").create_layout
    end
    require("telescope").setup(opts)
    -- the preview shows line numbers and the hit line across the whole width, like the demo's
    -- (the cursor sits on the hit; the extmark telescope paints only covers the text)
    vim.api.nvim_create_autocmd("User", {
      pattern = "TelescopePreviewerLoaded",
      callback = function()
        if flat.enabled() then
          require("ui.flat.telescope").on_preview_loaded()
          return
        end
        vim.wo.number = true
        vim.wo.cursorline = true
        vim.wo.cursorlineopt = "both"
        vim.wo.winhl = vim.wo.winhl .. ",CursorLine:TelescopePreviewLine"
      end,
    })
  end,
}
