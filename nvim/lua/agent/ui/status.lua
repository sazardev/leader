-- ── Visual state of a job, IN the code ───────────────────────────────────────
-- While it runs: the target stays highlighted (you see what was sent) and to the right of its
-- first line a spinner spins with action · model · seconds. When it ends a
-- summary stays for a few seconds and goes away by itself.
local jobs = require "agent.jobs"
local anchor = require "agent.anchor"
local selection = require "agent.selection"

require("agent.ui.highlights").ensure()

local M = {}

local NS = vim.api.nvim_create_namespace "agent.status"
local FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local SUMMARY_MS = 5000

---@param job AgentJob
local function stop_timer(job)
  local timer = job.timer
  if timer then
    job.timer = nil
    timer:stop()
    timer:close()
  end
end

--- Where the state is painted: the code being viewed (`view`, if the result goes to another file) or the target
---@param job AgentJob
---@return integer buf, integer anchor_id
local function spot(job)
  if job.view then
    return job.view.buf, job.view.anchor
  end
  return job.buf, job.anchor
end

---@param job AgentJob
function M.clear(job)
  stop_timer(job)
  local buf = spot(job)
  if job.status_mark and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_del_extmark, buf, NS, job.status_mark)
  end
  job.status_mark = nil
  if job.view and job.view.anchor then
    anchor.delete(job.view.buf, job.view.anchor)
    job.view.anchor = nil
  end
end

---@param job AgentJob
function M.attach(job)
  local tick = 0
  local function draw()
    if job.state ~= "running" then
      return -- an already queued redraw must not resurrect the mark after clear()
    end
    local buf, id = spot(job)
    local first, last = anchor.range(buf, id)
    if not first then
      return M.clear(job)
    end
    if job.view then
      job.view.first = first
    end
    tick = tick + 1
    -- in a narrow window the text on the right would cover code: compact version, without model
    local win = vim.fn.bufwinid(buf)
    local narrow = win ~= -1 and vim.api.nvim_win_get_width(win) < 90
    local text = narrow and (" %s %s %.0fs "):format(FRAMES[tick % #FRAMES + 1], job.action.label, jobs.elapsed(job))
      or (" %s %s · %s · %.1fs "):format(
        FRAMES[tick % #FRAMES + 1],
        job.action.label,
        selection.label(job.selection),
        jobs.elapsed(job)
      )
    -- what was estimated when it left (agent/trust.lua), unless the window is narrow or the user turned it off
    if not narrow and job.estimate and require("core.settings").agent.trust.preflight == "status" then
      text = text:gsub(" $", "") .. (" · ~%s tok "):format(require("agent.text").tokens(job.estimate.tokens))
    end
    local end_row, end_col = anchor.highlight_end(buf, last)
    job.status_mark = vim.api.nvim_buf_set_extmark(buf, NS, first - 1, 0, {
      id = job.status_mark,
      end_row = end_row,
      end_col = end_col,
      hl_group = "AgentTarget",
      hl_eol = true,
      virt_text = { { text, "AgentStatus" } },
      virt_text_pos = "right_align",
      strict = false,
    })
  end

  draw()
  job.timer = vim.uv.new_timer()
  job.timer:start(100, 100, vim.schedule_wrap(draw))
end

--- Replaces the spinner with a summary that fades by itself
---@param job AgentJob
---@param text string
function M.summary(job, text)
  M.clear(job)
  local buf = spot(job)
  local first = job.view and job.view.first or (anchor.range(job.buf, job.anchor) or job.target.first)
  if not vim.api.nvim_buf_is_valid(buf) or first > vim.api.nvim_buf_line_count(buf) then
    return
  end
  local mark = vim.api.nvim_buf_set_extmark(buf, NS, first - 1, 0, {
    virt_text = { { " " .. text .. " ", "AgentDone" } },
    virt_text_pos = "right_align",
    strict = false,
  })
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_del_extmark, buf, NS, mark)
    end
  end, SUMMARY_MS)
end

return M
