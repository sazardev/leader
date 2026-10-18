-- ── Build with agent · use: a command line program, run once per step ──────
-- Each step runs the program with the step's arguments and standard input; its screen is what it printed (standard
-- output, then standard error) and its exit code, which a scenario can expect (0 on success, non-zero on an error).
local async = require "agent.kit.build.use.async"

local M = {}

M.TIMEOUT_MS = 10000
M.MAX_OUTPUT = 6000

---@return boolean, string?
function M.available()
  return true
end

---@param ctx table
---@return string?
function M.prepare(ctx)
  return nil
end

--- What a run printed, as the screen of its step
---@param res { code: integer, stdout: string, stderr: string }
---@return string
function M.screen(res)
  local out = vim.trim(res.stdout or "")
  local err = vim.trim(res.stderr or "")
  local parts = {}
  if out ~= "" then
    parts[#parts + 1] = out
  end
  if err ~= "" then
    parts[#parts + 1] = "[stderr]\n" .. err
  end
  if res.code == 124 then
    parts[#parts + 1] = ("[still running after %ds: killed]"):format(M.TIMEOUT_MS / 1000)
  end
  parts[#parts + 1] = ("[exit %d]"):format(res.code)
  local text = table.concat(parts, "\n")
  if #text > M.MAX_OUTPUT then
    text = text:sub(1, M.MAX_OUTPUT) .. "\n…"
  end
  return text
end

---@param ctx table
---@param scenario UseScenario
---@return UseFrame[]?, string?
function M.play(ctx, scenario)
  local frames = {}
  for i, step in ipairs(scenario.steps) do
    local cmd = vim.deepcopy(ctx.launch.argv)
    vim.list_extend(cmd, step.args or {})
    local res = async.system(cmd, {
      cwd = ctx.root,
      stdin = step.stdin or false,
      timeout = M.TIMEOUT_MS,
      env = vim.tbl_extend("force", { NO_COLOR = "1", TERM = "dumb" }, ctx.launch.env or {}),
    })
    frames[#frames + 1] = {
      step = i,
      did = require("agent.kit.build.use.scenario").describe(step),
      screen = M.screen(res),
      exit = res.code,
    }
  end
  return frames
end

---@param ctx table
function M.finish(ctx) end

return M
