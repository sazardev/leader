-- ── Running a step of a diagnosis ────────────────────────────────────────────
-- A step is a command, an edit or something only a person can do. Nothing here runs without a yes that shows the exact
-- command: a command runs captured (its output and exit code come back into the diagnosis, and into what was tried), or in the
-- integrated terminal when it is interactive; an edit becomes one proposal with the usual inline diff; a manual step is
-- marked done by hand. `describe_tried` turns what happened into the lines the next request carries.
local evidence = require "agent.doctor.evidence"
local log = require "utils.log"
local settings = require("core.settings").agent.doctor

local M = {}

---@param step DoctorPlanStep
---@return string
function M.glyph(step)
  if step.state == "done" then
    return "✓"
  elseif step.state == "failed" then
    return "✗"
  end
  return step.kind == "command" and "▸" or step.kind == "edit" and "✎" or "·"
end

--- The last lines of an output, cleaned and with secrets out
---@param text string
---@param lines integer
---@return string
function M.tail(text, lines)
  local all = vim.split(evidence.redact(evidence.clean(text or "")), "\n", { plain = true })
  return table.concat(vim.list_slice(all, math.max(1, #all - lines + 1), #all), "\n")
end

--- What was attempted so far, as lines for the next request (never suggest it again)
---@param steps DoctorPlanStep[]
---@return string[]
function M.describe_tried(steps)
  local out = {}
  for _, s in ipairs(steps) do
    if s.kind == "command" and s.exit ~= nil then
      out[#out + 1] = ("ran `%s` → exit %d%s"):format(s.run, s.exit, s.output and s.output ~= "" and (":\n" .. M.tail(s.output, 12)) or "")
    elseif s.kind == "command" and s.state == "ran" then
      out[#out + 1] = ("ran `%s` in the terminal (result not captured)"):format(s.run)
    elseif s.kind == "edit" and s.state == "done" then
      out[#out + 1] = ("edited %s: %s"):format(s.file, s.instruction or s.title)
    elseif s.kind == "manual" and s.state == "done" then
      out[#out + 1] = ("did: %s"):format(s.title)
    end
  end
  return out
end

--- Runs a command captured. `done()` when it ends (step.state, exit and output are set)
---@param root string
---@param step DoctorPlanStep
---@param done fun()
function M.run_captured(root, step, done)
  step.state, step.output, step.exit = nil, nil, nil
  local cmd = { vim.o.shell, vim.o.shellcmdflag, step.run }
  local ok = pcall(vim.system, cmd, { cwd = root, text = true, timeout = settings.command_timeout_ms }, function(res)
    vim.schedule(function()
      step.exit = res.signal == 15 and 124 or res.code
      step.output = M.tail((res.stdout or "") .. "\n" .. (res.stderr or ""), 60)
      step.state = step.exit == 0 and "done" or "failed"
      done()
    end)
  end)
  if not ok then
    step.state, step.exit, step.output = "failed", 127, "could not start the shell"
    done()
  end
end

--- Runs a command in the integrated terminal (interactive things, servers); the result is not captured
---@param root string
---@param step DoctorPlanStep
function M.run_terminal(root, step)
  require("utils.terminal").run(step.run, root)
  step.state = "ran"
end

--- Asks before running; `go()` runs it
---@param step DoctorPlanStep
---@param where string "captured"|"terminal"
---@param go fun()
function M.confirm_command(step, where, go)
  local modal = require "utils.modal"
  local lines = {
    { { "$ " .. step.run, modal.hl.file } },
    "",
    {
      {
        where == "terminal" and "Runs in the integrated terminal: you see it, you can answer it, Ctrl-C stops it."
          or "Runs here, in the project folder; its output and exit code come back into the diagnosis.",
        modal.hl.muted,
      },
    },
  }
  if step.why then
    lines[#lines + 1] = { { step.why, modal.hl.muted } }
  end
  if step.danger then
    lines[#lines + 1] = ""
    lines[#lines + 1] = { { "This command destroys or rewrites something. Read it twice.", modal.hl.warn } }
  end
  modal.confirm(lines, { title = step.title, confirm = "Run", danger = step.danger }, go)
end

--- The range an edit step works on: the function around its line, else a window around it, else the whole (small) file
---@param buf integer
---@param line integer?
---@return integer first, integer last
local function range_for(buf, line)
  local total = vim.api.nvim_buf_line_count(buf)
  if line and line >= 1 and line <= total then
    local found = require("agent.fixall").resolver(buf)(line)
    if found and found.last - found.first < 200 then
      return found.first, found.last
    end
    return math.max(1, line - 15), math.min(total, line + 15)
  end
  return 1, math.min(total, 150)
end

--- An edit step as one proposal (the usual inline diff, accept/reject, the queue). `on_started` runs once it is under way
---@param root string
---@param step DoctorPlanStep
---@param diagnosis DoctorDiagnosis
---@param on_started fun()?
function M.apply_edit(root, step, diagnosis, on_started)
  local abs = require("agent.doctor.tools").readable(root, step.file)
  if not abs then
    return log.warn("Doctor: " .. step.file .. " is outside the project or holds secrets: edit it yourself")
  end
  if vim.fn.filereadable(abs) ~= 1 then
    return log.warn("Doctor: " .. step.file .. " does not exist")
  end
  if on_started then
    on_started()
  end
  vim.cmd.edit(vim.fn.fnameescape(abs))
  local buf = vim.api.nvim_get_current_buf()
  local first, last = range_for(buf, step.line)
  local target, err = require("agent.context.target").of_range(buf, "lines", first, last, "doctor")
  if not target then
    return log.warn("Doctor: " .. tostring(err))
  end
  pcall(vim.api.nvim_win_set_cursor, 0, { first, 0 })
  require("agent.batch").run {
    title = "doctor: " .. step.title,
    action = require("agent.doctor.action").build(),
    items = {
      {
        label = step.title,
        target = target,
        extra = {
          {
            name = "diagnosis",
            text = ("Cause: %s\nChange to make: %s%s"):format(diagnosis.cause, step.instruction or step.title, step.why and ("\nWhy: " .. step.why) or ""),
          },
        },
      },
    },
    meta = { doctor_step = step },
    header = { { { diagnosis.summary ~= "" and diagnosis.summary or step.title, require("utils.modal").hl.warn } } },
  }
end

return M
