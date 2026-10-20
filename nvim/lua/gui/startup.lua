-- ── Desktop app: what opens when it starts ──────────────────────────────────
-- An IDE opens a project, not an empty editor:
--   leader <folder>       that folder as the project (its session back, or the start screen)
--   leader <files…>       those files, nothing asked
--   leader (in a repo)    that repo: launched from a terminal inside a project, or by
--                         "new window" on a project (the app starts there)
--   leader (anywhere else, the desktop entry starts in ~): settings.gui.window.on_start
--     "ask"   the project picker over the start screen (the default)
--     "last"  the project opened last
--     "home"  the start screen
-- The first launch is the guided setup's: nothing is asked under it (its last step
-- offers Open a project, and Finish opens the picker when on_start is "ask").
local settings = require "core.settings"

local M = {}

--- A folder worth opening as a project by itself: a git repository that is not the home folder.
---@param dir string
---@return boolean
function M.is_project(dir)
  local projects = require "gui.projects"
  dir = projects.normalize(dir)
  return dir ~= projects.normalize "~" and dir ~= "/" and vim.uv.fs_stat(dir .. "/.git") ~= nil
end

---@return "ask"|"last"|"home"
function M.on_start()
  local v = (settings.gui.window or {}).on_start
  return (v == "last" or v == "home") and v or "ask"
end

--- What to do for this start (pure over its inputs, tested): "enter" a folder, "ask", or nothing.
---@param ctx { args: string[], empty: boolean, cwd: string, on_start: string, first_launch: boolean, last: string? }
---@return "enter"|"ask"|nil what, string? dir
function M.decide(ctx)
  if #ctx.args == 1 and vim.fn.isdirectory(ctx.args[1]) == 1 then
    return "enter", ctx.args[1]
  end
  if #ctx.args > 0 or not ctx.empty then
    return nil
  end
  if M.is_project(ctx.cwd) then
    return "enter", ctx.cwd
  end
  if ctx.first_launch or ctx.on_start == "home" then
    return nil
  end
  if ctx.on_start == "last" and ctx.last then
    return "enter", ctx.last
  end
  return "ask"
end

--- The picker, unless something else took the screen meanwhile (a file opened, the setup).
function M.ask()
  local wizard = package.loaded["gui.wizard"]
  if (wizard and wizard.current) or vim.bo.filetype ~= "nvdash" then
    return
  end
  require("gui.picker").open()
end

function M.setup()
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      local empty = vim.api.nvim_buf_get_name(0) == ""
        and vim.api.nvim_buf_line_count(0) == 1
        and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == ""
      local last = require("gui.projects").list()[1]
      local what, dir = M.decide {
        args = vim.fn.argv() --[[@as string[] ]],
        empty = empty or vim.bo.filetype == "nvdash",
        cwd = vim.uv.cwd() or "",
        on_start = M.on_start(),
        first_launch = settings.gui.onboarding ~= false and not require("gui.state").read().welcomed,
        last = last and last.dir or nil,
      }
      -- after the start screen's own VimEnter, so whatever opens lands over it
      vim.schedule(function()
        local ok, err = pcall(function()
          if what == "enter" then
            require("gui.projects").enter(dir)
          elseif what == "ask" then
            M.ask()
          end
        end)
        -- whatever opened is on the screen (or failed to): the app may draw its first frame
        require("gui").release()
        if not ok then
          error(err, 0)
        end
      end)
    end,
  })
end

return M
