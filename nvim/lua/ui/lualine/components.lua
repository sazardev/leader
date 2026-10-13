-- ── lualine components ───────────────────────────────────────────────────────
local M = {}

-- ── Diagnostics ──────────────────────────────────────────────────────────────
-- Errors and warnings separately (one never hides the other), as solid labels with the
-- severity color. They only count; the detail is in the code. The colors come from
-- ui/diagcolors.lua, the same as the line number and the inline blocks.
local SEVERITY = vim.diagnostic.severity
local LETTER = { [SEVERITY.ERROR] = "E", [SEVERITY.WARN] = "W" }

---@param severity integer
---@return table lualine color: background = severity accent, readable text on top
local function pill_color(severity)
  local diag = require "ui.diagcolors"
  diag.sync() -- if the theme changed, the line number and the blocks are recomputed with this bar
  local pill = diag.pill(severity)
  return { fg = pill.fg, bg = pill.bg, gui = "bold" }
end

--- Label " E2 " / " W1 " (empty if there are none of that severity; `cond` hides it)
---@param severity integer
---@return table lualine component
function M.diagnostic_count(severity)
  return {
    function()
      return (" %s%d "):format(LETTER[severity], vim.diagnostic.count(0)[severity] or 0)
    end,
    cond = function()
      return (vim.diagnostic.count(0)[severity] or 0) > 0
    end,
    color = function()
      return pill_color(severity)
    end,
    padding = 0,
  }
end

-- ── Agent ────────────────────────────────────────────────────────────────────
--- Spinner while agent actions are running. It does not load the agent: if it was never used
--- (module not loaded) there is nothing to show.
---@return table lualine component
function M.agent_status()
  return {
    function()
      local jobs = package.loaded["agent.jobs"]
      return jobs and jobs.statusline() or ""
    end,
    cond = function()
      local jobs = package.loaded["agent.jobs"]
      return jobs ~= nil and #jobs.running() > 0
    end,
    color = "AgentStatus",
    padding = 0,
  }
end

---@return string name of the working folder
function M.project_name()
  local cwd = vim.uv.cwd() or ""
  return cwd:match "([^/\\]+)[/\\]*$" or cwd
end

---@return boolean
function M.is_wide()
  return vim.o.columns > 85
end

return M
