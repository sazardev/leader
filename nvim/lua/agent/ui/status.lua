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

--- Dónde se pinta el estado: el código que se mira (`view`, si el resultado va a otro archivo) o el objetivo
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
      return -- un redibujado ya encolado no debe resucitar la marca tras clear()
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
    -- en una ventana estrecha el texto de la derecha taparía código: versión compacta, sin modelo
    local win = vim.fn.bufwinid(buf)
    local narrow = win ~= -1 and vim.api.nvim_win_get_width(win) < 90
    local text = narrow and (" %s %s %.0fs "):format(FRAMES[tick % #FRAMES + 1], job.action.label, jobs.elapsed(job))
      or (" %s %s · %s · %.1fs "):format(
        FRAMES[tick % #FRAMES + 1],
        job.action.label,
        selection.label(job.selection),
        jobs.elapsed(job)
      )
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

--- Reemplaza el spinner por un resumen que se apaga solo
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
