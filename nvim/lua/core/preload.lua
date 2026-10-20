-- ── Idle preloading ──────────────────────────────────────────────────────────
-- What the first keypress of a session would otherwise pay for: Telescope's modules (the first `<leader>ff` builds its
-- picker ~25 ms faster once they are loaded). It runs a moment after startup, one small step per tick so typing is never
-- held up, and never in light mode (a low-RAM machine keeps only what is used).
local settings = require "core.settings"

local M = {}

local TELESCOPE = {
  "telescope.builtin",
  "telescope.pickers",
  "telescope.finders",
  "telescope.config",
  "telescope.actions",
  "telescope.actions.state",
  "telescope.make_entry",
  "telescope.previewers",
  "telescope.sorters",
}

--- The steps, in order; each one is small enough to run between two keystrokes.
---@return (fun())[]
function M.steps()
  local steps = {
    function()
      require("lazy").load { plugins = { "telescope.nvim" } }
    end,
  }
  for _, mod in ipairs(TELESCOPE) do
    steps[#steps + 1] = function()
      pcall(require, mod)
    end
  end
  return steps
end

function M.setup()
  local cfg = settings.preload
  if not cfg.enabled or require("core.light").enabled then
    return
  end
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      vim.defer_fn(function()
        local steps, i = M.steps(), 0
        local function next_step()
          i = i + 1
          if steps[i] then
            pcall(steps[i])
            vim.defer_fn(next_step, 5)
          end
        end
        next_step()
      end, cfg.delay_ms)
    end,
  })
end

return M
