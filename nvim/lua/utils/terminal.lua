-- ── Integrated terminal (toggleterm) ─────────────────────────────────────────
-- Position and size come from settings.terminal and are recalculated on every open
-- and when the window is resized (responsive).
local settings = require "core.settings"

local M = {}

--- toggleterm direction according to the current screen width
---@return "vertical"|"horizontal"|"float"
function M.direction()
  local cfg = settings.terminal
  if cfg.position == "float" then
    return "float"
  end
  if cfg.position == "bottom" or vim.o.columns < cfg.narrow_columns then
    return "horizontal"
  end
  return "vertical"
end

--- Size (columns or lines) for a toggleterm terminal
---@param term { direction: string }
---@return number
function M.size(term)
  local cfg = settings.terminal
  if term.direction == "vertical" then
    return math.max(cfg.min_width, math.floor(vim.o.columns * cfg.width))
  end
  return math.max(cfg.min_height, math.floor(vim.o.lines * cfg.height))
end

--- Adjust open terminals after a window resize
function M.refresh()
  for _, term in pairs(require("toggleterm.terminal").get_all()) do
    if term:is_open() and term:is_split() then
      -- toggleterm resizes the current window: it has to be done from the terminal's window
      vim.api.nvim_win_call(term.window, function()
        term:resize(M.size(term))
      end)
    end
  end
end

--- Keys of a terminal buffer, the same for toggleterm's and NvChad's: Esc closes the window (`close`; the
--- shell keeps running), Shift+Esc only hands the focus back to the previous window and leaves the terminal open
---@param buf integer
---@param close fun()
function M.attach_keys(buf, close)
  local function map(lhs, rhs, desc)
    vim.keymap.set({ "n", "t" }, lhs, rhs, { buffer = buf, desc = desc })
  end
  map("<Esc>", close, "Terminal close (Esc)")
  map("<S-Esc>", function()
    vim.cmd "stopinsert"
    -- toggleterm closes its floats on WinLeave: skip that event for this one jump so the terminal stays
    local ignore = vim.o.eventignore
    vim.opt.eventignore:append "WinLeave"
    pcall(vim.cmd, "wincmd p")
    vim.o.eventignore = ignore
  end, "Terminal unfocus (Shift+Esc)")
end

--- Run `cmd` in the integrated terminal with cwd `dir`
---@param cmd string
---@param dir string
function M.run(cmd, dir)
  local direction = M.direction()
  -- a closed terminal keeps its previous direction: we update it
  for _, term in pairs(require("toggleterm.terminal").get_all()) do
    if not term:is_open() then
      term.direction = direction
    end
  end
  vim.cmd(("TermExec cmd=%s dir=%s direction=%s"):format(vim.fn.shellescape(cmd), vim.fn.shellescape(dir), direction))
end

return M
