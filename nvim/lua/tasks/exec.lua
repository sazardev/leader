-- ── Running a task ───────────────────────────────────────────────────────────
-- A task runs in the integrated terminal (`utils/terminal.lua`): you see it, you can answer it, Ctrl-C works, and
-- the agent's "fix from output" reads that same terminal. `line` is pure. A task that is still running there would receive
-- the next command as its own input, so `run` asks first and `stop` sends it Ctrl-C.
local util = require "tasks.util"

local M = {}

--- The shell line of a task, with what you typed after it
---@param task Task
---@param extra string?
---@return string
function M.line(task, extra)
  local line = util.quote(task.cmd)
  extra = extra and vim.trim(extra) or ""
  if extra ~= "" then
    line = line .. " " .. extra
  end
  return line
end

--- The terminal tasks use (toggleterm's first), only if one was ever opened: lazy.nvim has not even loaded it before
---@return table?
local function term()
  local ok, terminals = pcall(require, "toggleterm.terminal")
  if not ok then
    return nil
  end
  local t = terminals.get(1, true)
  return t and t.job_id and t or nil
end

--- Is something running in that terminal besides its shell?
---@return boolean
function M.busy()
  local t = term()
  if not t then
    return false
  end
  local ok, pid = pcall(vim.fn.jobpid, t.job_id)
  if not ok then
    return false
  end
  local alive, children = pcall(vim.api.nvim_get_proc_children, pid)
  return alive and #children > 0
end

--- Ctrl-C to whatever runs in the task terminal
---@return boolean sent
function M.stop()
  local t = term()
  if not t or not M.busy() then
    return false
  end
  vim.fn.chansend(t.job_id, "\3")
  return true
end

---@param task Task
---@param extra string?
local function go(task, extra)
  require("utils.terminal").run(M.line(task, extra), task.cwd)
end

--- Starts the task. If another one is still running it asks first (`on_start` runs when it really starts)
---@param task Task
---@param extra string?
---@param on_start fun()?
function M.run(task, extra, on_start)
  if vim.fn.isdirectory(task.cwd) ~= 1 then
    return require("utils.log").warn("Tasks: " .. task.cwd .. " no longer exists")
  end
  local function start()
    go(task, extra)
    if on_start then
      on_start()
    end
  end
  if not M.busy() then
    return start()
  end
  local modal = require "utils.modal"
  modal.confirm({
    "A task is still running in the terminal.",
    { { M.line(task, extra), modal.hl.muted } },
  }, { title = "Run " .. task.name, confirm = "Stop it and run" }, function()
    M.stop()
    vim.defer_fn(start, 400)
  end)
end

return M
