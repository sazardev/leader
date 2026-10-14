-- ── The plan, for you to edit before anything is spent ───────────────────────
-- A reading panel (agent/ui/panel) with one checkbox line per step. Space toggles a step, `a` all or none, Enter runs the
-- checked ones, q cancels. The first line keeps the estimate up to date as you toggle: what you see is what you pay.
local panel = require "agent.ui.panel"

local M = {}

local HEADER_ROWS = 4 -- lines before the first step

---@param step table
---@return string
local function line_of(step)
  return ("- [%s] %d. `%s` · **%s** — %s"):format(step.on and "x" or " ", step.n, step.path, step.symbol, step.what)
end

--- Panel lines
---@param instruction string
---@param steps table[]
---@param status string
---@return string[]
function M.lines(instruction, steps, status)
  local lines = { "# Plan", "", ("_%s_"):format(status), "" }
  lines[#lines + 1] = ("**%s**"):format(instruction)
  lines[#lines + 1] = ""
  for _, step in ipairs(steps) do
    lines[#lines + 1] = line_of(step)
  end
  return lines
end

local FIRST_STEP_ROW = HEADER_ROWS + 3 -- header, instruction and a blank line precede the steps

---@param opts { instruction: string, steps: table[], status: fun(chosen: table[]): string, on_run: fun(chosen: table[]) }
function M.open(opts)
  local steps = opts.steps
  local function chosen()
    return vim.tbl_filter(function(s)
      return s.on
    end, steps)
  end
  panel.open(M.lines(opts.instruction, steps, opts.status(chosen())), ("Plan · %d steps"):format(#steps), {
    hint = "Space toggle · a all/none · Enter run · q cancel",
    on_open = function(buf, _, close)
      local function redraw()
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.lines(opts.instruction, steps, opts.status(chosen())))
        vim.bo[buf].modifiable = false
      end
      local function step_at_cursor()
        return steps[vim.api.nvim_win_get_cursor(0)[1] - FIRST_STEP_ROW + 1]
      end
      local function map(key, fn, desc)
        vim.keymap.set("n", key, fn, { buffer = buf, nowait = true, desc = "Agent plan " .. desc })
      end
      map("<Space>", function()
        local step = step_at_cursor()
        if step then
          step.on = not step.on
          redraw()
        end
      end, "toggle step")
      map("a", function()
        local any_off = #chosen() < #steps
        for _, s in ipairs(steps) do
          s.on = any_off
        end
        redraw()
      end, "all or none")
      map("<CR>", function()
        local picked = chosen()
        if #picked == 0 then
          return require("utils.log").info "Agent: no step is checked"
        end
        close()
        opts.on_run(picked)
      end, "run")
    end,
  })
end

return M
