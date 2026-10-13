-- ── Ventana de respuesta, junto al código ────────────────────────────────────
-- Una sola ventana flotante tipo tooltip, anclada bajo (o sobre) el código sobre el que
-- preguntaste; crece mientras llega el texto en streaming. Markdown (con
-- render-markdown si está). Se cierra sola al seguir editando; `<leader>al` la reabre
-- y entra en ella (q/<Esc> cierran).
local anchor = require "agent.anchor"

require("agent.ui.highlights").ensure()

local M = {}

local MAX_WIDTH = 84
local MAX_HEIGHT = 20

---@class AgentFloatState
---@field buf integer?
---@field win integer?
---@field job_id integer?
---@field from integer  buffer de código
---@field first integer  1-based
---@field last integer  1-based
---@field title string
local state = { title = "" }

---@return boolean
local function is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

function M.close()
  if is_open() then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
end

---@param lines string[]
---@param width integer
---@return integer
local function wrapped_height(lines, width)
  local h = 0
  for _, l in ipairs(lines) do
    h = h + math.max(1, math.ceil(vim.fn.strdisplaywidth(l) / width))
  end
  return math.min(math.max(h, 3), MAX_HEIGHT)
end

--- Dónde va: debajo de la última línea si cabe, si no encima de la primera
---@param width integer
---@param height integer
---@return table
local function placement(width, height)
  local code_win = vim.fn.bufwinid(state.from)
  if code_win == -1 then
    code_win = vim.api.nvim_get_current_win()
  end
  local below = vim.o.lines - (vim.fn.screenpos(code_win, state.last, 1).row or 0) - 3
  local above = (vim.fn.screenpos(code_win, state.first, 1).row or 0) - 3
  local use_below = below >= math.min(height + 2, 10) or below >= above
  return {
    relative = "win",
    win = code_win,
    bufpos = { (use_below and state.last or state.first) - 1, 0 },
    anchor = use_below and "NW" or "SW",
    height = math.max(3, math.min(height, use_below and below or above)),
    width = width,
  }
end

--- Ancho = la línea más larga (con tope), alto = líneas ya envueltas a ese ancho
---@param lines string[]
---@return integer width, integer height
local function fit(lines)
  local longest = 0
  for _, l in ipairs(lines) do
    longest = math.max(longest, vim.fn.strdisplaywidth(l))
  end
  local cap = math.min(MAX_WIDTH, math.max(30, vim.api.nvim_win_get_width(0) - 8))
  local width = math.min(cap, math.max(30, longest + 2))
  return width, wrapped_height(lines, width)
end

---@param enter boolean
local function open_window(enter)
  local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
  local cfg = placement(fit(lines))
  state.win = vim.api.nvim_open_win(
    state.buf,
    enter,
    vim.tbl_extend("force", cfg, {
      style = "minimal",
      border = "single",
      title = (" %s "):format(state.title),
      title_pos = "left",
      focusable = true,
    })
  )
  local wo = vim.wo[state.win]
  wo.wrap = true
  wo.linebreak = true
  wo.winhighlight = "NormalFloat:AgentFloat,FloatBorder:AgentBorder,FloatTitle:AgentTitle"
end

local function new_buffer()
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].bufhidden = "hide"
  vim.bo[state.buf].filetype = "markdown"
  vim.diagnostic.enable(false, { bufnr = state.buf })
  for _, key in ipairs { "q", "<Esc>" } do
    vim.keymap.set("n", key, M.close, { buffer = state.buf, nowait = true, desc = "Agent close answer" })
  end
end

--- Muestra (o actualiza) el texto de un trabajo
---@param job AgentJob
---@param body string
---@param title string
function M.show(job, body, title)
  if state.job_id ~= job.id or not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    M.close()
    state.job_id = job.id
    state.from = job.buf
    state.first, state.last = anchor.range(job.buf, job.anchor)
    state.first = state.first or vim.api.nvim_win_get_cursor(0)[1]
    state.last = state.last or state.first
    new_buffer()
  end
  state.title = title

  local lines = vim.split(body, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  if not is_open() then
    open_window(false)
  else
    local cfg = placement(fit(lines))
    vim.api.nvim_win_set_config(state.win, {
      width = cfg.width,
      height = cfg.height,
      title = (" %s "):format(title),
      title_pos = "left",
    })
  end
  pcall(vim.api.nvim_win_set_cursor, state.win, { #lines, 0 })
end

--- Cierra la ventana cuando sigues trabajando en el código (como un tooltip)
---@param job AgentJob
function M.autoclose(job)
  vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter" }, {
    buffer = job.buf,
    once = true,
    callback = function()
      if state.job_id == job.id then
        M.close()
      end
    end,
  })
end

--- Quita la ventana si pertenece a este trabajo (fallo / cancelación)
---@param job AgentJob
function M.discard(job)
  if state.job_id == job.id then
    M.close()
  end
end

--- Reabre la última respuesta y entra en ella
---@return boolean
function M.reopen()
  if is_open() then
    vim.api.nvim_set_current_win(state.win)
    return true
  end
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    return false
  end
  state.from = vim.api.nvim_get_current_buf()
  state.first = vim.api.nvim_win_get_cursor(0)[1]
  state.last = state.first
  open_window(true)
  return true
end

return M
