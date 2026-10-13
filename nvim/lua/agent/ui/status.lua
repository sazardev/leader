-- ── Estado visual de un trabajo, EN el código ────────────────────────────────
-- Mientras corre: el objetivo queda resaltado (ves qué se envió) y a la derecha de su
-- primera línea gira un spinner con acción · modelo · segundos. Al terminar queda un
-- resumen unos segundos y se va solo.
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

---@param job AgentJob
function M.clear(job)
  stop_timer(job)
  if job.status_mark and vim.api.nvim_buf_is_valid(job.buf) then
    pcall(vim.api.nvim_buf_del_extmark, job.buf, NS, job.status_mark)
  end
  job.status_mark = nil
end

---@param job AgentJob
function M.attach(job)
  local tick = 0
  local function draw()
    if job.state ~= "running" then
      return -- un redibujado ya encolado no debe resucitar la marca tras clear()
    end
    local first, last = anchor.range(job.buf, job.anchor)
    if not first then
      return M.clear(job)
    end
    tick = tick + 1
    -- en una ventana estrecha el texto de la derecha taparía código: versión compacta, sin modelo
    local win = vim.fn.bufwinid(job.buf)
    local narrow = win ~= -1 and vim.api.nvim_win_get_width(win) < 90
    local text = narrow and (" %s %s %.0fs "):format(FRAMES[tick % #FRAMES + 1], job.action.label, jobs.elapsed(job))
      or (" %s %s · %s · %.1fs "):format(
        FRAMES[tick % #FRAMES + 1],
        job.action.label,
        selection.label(job.selection),
        jobs.elapsed(job)
      )
    local end_row, end_col = anchor.highlight_end(job.buf, last)
    job.status_mark = vim.api.nvim_buf_set_extmark(job.buf, NS, first - 1, 0, {
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

--- Reemplaza el spinner por un resumen que se apaga solo
---@param job AgentJob
---@param text string
function M.summary(job, text)
  M.clear(job)
  local first = anchor.range(job.buf, job.anchor) or job.target.first
  if not vim.api.nvim_buf_is_valid(job.buf) or first > vim.api.nvim_buf_line_count(job.buf) then
    return
  end
  local mark = vim.api.nvim_buf_set_extmark(job.buf, NS, first - 1, 0, {
    virt_text = { { " " .. text .. " ", "AgentDone" } },
    virt_text_pos = "right_align",
    strict = false,
  })
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(job.buf) then
      pcall(vim.api.nvim_buf_del_extmark, job.buf, NS, mark)
    end
  end, SUMMARY_MS)
end

return M
