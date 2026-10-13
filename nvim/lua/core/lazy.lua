-- ── lazy.nvim bootstrap and startup ──────────────────────────────────────────
local M = {}

-- Plugin groups: each lua/plugins/<group>/ folder is imported whole
-- (one file = one plugin or one feature). Add groups here.
local GROUPS = { "core", "lsp", "tools", "syntax", "languages", "navigation", "editing", "git", "ui" }

local OPTIONS = {
  defaults = { lazy = true },
  install = { colorscheme = { "nvchad" } },

  -- No plugin uses rocks: avoids the hererocks ERROR in :checkhealth lazy
  rocks = { enabled = false },

  ui = {
    icons = {
      ft = ">>",
      lazy = "~",
      loaded = "o",
      not_loaded = "x",
    },
  },

  performance = {
    rtp = {
      disabled_plugins = {
        "2html_plugin",
        "tohtml",
        "getscript",
        "getscriptPlugin",
        "gzip",
        "logipat",
        "netrw",
        "netrwPlugin",
        "netrwSettings",
        "netrwFileHandlers",
        "matchit",
        "tar",
        "tarPlugin",
        "rrhelper",
        "spellfile_plugin",
        "vimball",
        "vimballPlugin",
        "zip",
        "zipPlugin",
        "tutor",
        "rplugin",
        "syntax",
        "synmenu",
        "optwin",
        "compiler",
        "bugreport",
        "ftplugin",
      },
    },
  },
}

local function bootstrap()
  local path = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"
  if not vim.uv.fs_stat(path) then
    local out = vim.fn.system {
      "git",
      "clone",
      "--filter=blob:none",
      "--branch=stable",
      "https://github.com/folke/lazy.nvim.git",
      path,
    }
    if vim.v.shell_error ~= 0 then
      error("Failed to clone lazy.nvim:\n" .. out)
    end
  end
  vim.opt.rtp:prepend(path)
end

function M.setup()
  bootstrap()

  local spec = {
    { "NvChad/NvChad", lazy = false, branch = "v2.5", import = "nvchad.plugins" },
  }
  for _, group in ipairs(GROUPS) do
    table.insert(spec, { import = "plugins." .. group })
  end

  require("lazy").setup(spec, OPTIONS)
end

return M
