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
      prompt_prefix = "> ",
      selection_caret = "  ",
      -- flat: results above, the prompt right under them, preview on the right; the (blank) border cells are the gaps
      -- between the blocks, painted by ui/flat. Best match sits next to the prompt.
      sorting_strategy = "descending",
      border = true,
      borderchars = { " ", " ", " ", " ", " ", " ", " ", " " },
      results_title = "Results",
      preview_title = "Preview",
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
      buffers = { entry_maker = no_icons() },
      oldfiles = { entry_maker = no_icons() },
    },
  },
  config = function(_, opts)
    require("telescope").setup(opts)
    -- the preview shows line numbers and the hit line across the whole width, like the demo's
    -- (the cursor sits on the hit; the extmark telescope paints only covers the text)
    vim.api.nvim_create_autocmd("User", {
      pattern = "TelescopePreviewerLoaded",
      callback = function()
        vim.wo.number = true
        vim.wo.cursorline = true
        vim.wo.cursorlineopt = "both"
        vim.wo.winhl = vim.wo.winhl .. ",CursorLine:TelescopePreviewLine"
      end,
    })
  end,
}
