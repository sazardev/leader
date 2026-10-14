-- ── Flat design ──────────────────────────────────────────────────────────────
-- One module that gives the whole editor the look of the landing page's demo: filled blocks instead of boxes,
-- selection in solid blue, yellow matches and keys, purple groups, faint hints, and a "just changed" flash.
-- `palette.lua` derives a handful of tokens from the active theme, `groups.lua` turns them into highlight groups,
-- and this file applies them whenever the theme (or a plugin that defines its own colors) changes.
-- Plugins read `M.BORDER` (or inherit 'winborder') for their `border` option and `FloatBorder` makes it invisible.
-- Off with `settings.ui.flat = false`.
local settings = require "core.settings"

local M = {}

--- `solid` = one blank cell of padding around the content; with `FloatBorder` painted like the block it is air, not a line
M.BORDER = "solid"

--- Border for a window: invisible padding when flat, the usual line otherwise (what plugins pass as `border`)
---@return string
function M.border()
  return M.enabled() and M.BORDER or "single"
end

---@return boolean
function M.enabled()
  return settings.ui.flat ~= false
end

local emitting = false

--- Defines every group from the active theme
function M.apply()
  if not M.enabled() then
    return
  end
  local defs = require("ui.flat.groups").build(require("ui.flat.palette").current())
  for name, def in pairs(defs) do
    vim.api.nvim_set_hl(0, name, def)
  end
  -- what derives its own colors from NormalFloat / Normal (agent, commit panel) recomputes now, not on the next theme change
  emitting = true
  vim.api.nvim_exec_autocmds("User", { pattern = "NvThemeReload", modeline = false })
  emitting = false
end

local pending = false

--- Same, once per tick however many plugins asked for it
function M.request()
  if pending then
    return
  end
  pending = true
  vim.schedule(function()
    pending = false
    M.apply()
  end)
end

function M.setup()
  if not M.enabled() then
    return
  end
  local ui = settings.ui

  vim.o.winborder = M.BORDER
  vim.opt.fillchars:append { vert = "│" }
  if ui.blink_cursor then
    vim.o.guicursor = "n-v-c-sm:block,i-ci-ve:ver25,r-cr-o:hor20,a:blinkwait700-blinkoff400-blinkon250"
  end

  local group = vim.api.nvim_create_augroup("FlatDesign", { clear = true })
  -- the theme changed, or a plugin just loaded and painted its own groups on top of ours
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = M.request })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "NvThemeReload", "LazyLoad", "VeryLazy" },
    callback = function()
      if not emitting then
        M.request()
      end
    end,
  })
  vim.api.nvim_create_autocmd("TextYankPost", {
    group = group,
    callback = function()
      require("ui.flat.fresh").on_yank()
    end,
  })

  if ui.notify then
    require("ui.flat.notify").setup()
  end
  require("ui.flat.keys").setup()
  M.apply()
end

return M
