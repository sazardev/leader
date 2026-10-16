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

--- The agent build (<leader>aSb) while it runs, from any buffer: "⠹ build 7/25 · $0.031". It does not load the build: no
--- state module loaded = nothing to show.
---@return table lualine component
function M.build_status()
  local function text()
    local state = package.loaded["agent.kit.build.state"]
    return state and state.statusline() or ""
  end
  return {
    text,
    cond = function()
      return text() ~= ""
    end,
    color = "AgentStatus",
    padding = 0,
  }
end

--- build_runner (dartgen): "gen …" / "gen" / "gen ✗ N" while a watch or build runs for this file's package
function M.dartgen_status()
  local function text()
    local gen = package.loaded["dartgen"]
    return gen and gen.statusline() or ""
  end
  return {
    function()
      return " " .. text() .. " "
    end,
    cond = function()
      return text() ~= ""
    end,
    color = function()
      return text():find("✗", 1, true) and "DartgenFailed" or "DartgenStatus"
    end,
    padding = 0,
  }
end

--- Flutter app (dartrun): "▶ Pixel 7" while it runs
function M.flutter_status()
  local function text()
    -- also when the app was started with :FlutterRun: only flutter-tools has to be loaded
    return package.loaded["flutter-tools.commands"] and require("dartrun").statusline() or ""
  end
  return {
    function()
      return " " .. text() .. " "
    end,
    cond = function()
      return text() ~= ""
    end,
    color = "FlutterRunning",
    padding = 0,
  }
end

--- Dart tests (darttest): "test ✓12 ✗1 …" while a run is going; red as soon as one fails
function M.darttest_status()
  local function text()
    local tests = package.loaded["darttest"]
    return tests and tests.statusline() or ""
  end
  return {
    function()
      return " " .. text() .. " "
    end,
    cond = function()
      return text() ~= ""
    end,
    color = function()
      -- lualine evaluates this at setup too, before any test module is loaded
      local tests = package.loaded["darttest"]
      return tests and tests.failing() and "DartgenFailed" or "DartgenStatus"
    end,
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

--- `line:col`, like the demo's position chip
---@return string
function M.position()
  local pos = vim.api.nvim_win_get_cursor(0)
  return ("%d:%d"):format(pos[1], vim.fn.virtcol ".")
end

--- A `fmt` that centers the text in `width` columns: chips that keep their size while the text changes
---@param width integer
---@return fun(text: string): string
function M.centered(width)
  return function(text)
    local pad = width - vim.fn.strdisplaywidth(text)
    if pad <= 0 then
      return text
    end
    local left = math.floor(pad / 2)
    return (" "):rep(left) .. text .. (" "):rep(pad - left)
  end
end

return M
