-- ── Presentador "replace": propuesta en línea, aceptar/rechazar ──────────────
-- El resultado NO toca el buffer: se pinta como diff sobre el código (ui/preview) y
-- esperas tu decisión. Aceptar = un solo set_lines (un `u` lo deshace entero). Si
-- el código cambió mientras el agente trabajaba, se descarta en vez de pisarlo.
local anchor = require "agent.anchor"
local log = require "utils.log"
local preview = require "agent.ui.preview"
local protocol = require "agent.protocol"
local runs = require "agent.runs"
local settings = require("core.settings").agent
local stats = require "agent.stats"

local M = {}

---@class AgentProposal
---@field job AgentJob
---@field lines string[]
---@field ids integer[]

---@type table<integer, AgentProposal[]>
local proposals = {}

---@type table<string, string>
local KEY_LABEL = { ["<CR>"] = "⏎", ["<Esc>"] = "⎋", ["<Tab>"] = "⇥" }

---@param key string
---@return string
local function label(key)
  return KEY_LABEL[key] or key
end

---@param buf integer
local function bind(buf)
  local keys = settings.keys
  vim.keymap.set("n", keys.accept, M.accept, { buffer = buf, nowait = true, desc = "Agent accept proposal" })
  vim.keymap.set("n", keys.reject, M.reject, { buffer = buf, nowait = true, desc = "Agent reject proposal" })
end

---@param buf integer
local function unbind(buf)
  for _, key in pairs(settings.keys) do
    pcall(vim.keymap.del, "n", key, { buffer = buf })
  end
end

--- La propuesta del cursor; si no hay, la más antigua del buffer
---@param buf integer
---@return AgentProposal?
local function current(buf)
  local list = proposals[buf]
  if not list or #list == 0 then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  for _, p in ipairs(list) do
    local first, last = anchor.range(buf, p.job.anchor)
    if first and row >= first and row <= last then
      return p
    end
  end
  return list[1]
end

---@param p AgentProposal
local function drop(p)
  local buf = p.job.buf
  preview.clear(buf, p.ids)
  anchor.delete(buf, p.job.anchor)
  local list = proposals[buf] or {}
  for i, other in ipairs(list) do
    if other == p then
      table.remove(list, i)
      break
    end
  end
  if #list == 0 then
    proposals[buf] = nil
    if vim.api.nvim_buf_is_valid(buf) then
      unbind(buf)
    end
  end
end

--- Quita bordes en blanco que el modelo añadió y el objetivo no tenía
---@param code string[]
---@param target AgentTarget
---@return string[]
local function normalize(code, target)
  local function blank(l)
    return l == nil or not l:match "%S"
  end
  while #code > 0 and blank(code[#code]) and not blank(target.lines[#target.lines]) do
    table.remove(code)
  end
  while #code > 0 and blank(code[1]) and not blank(target.lines[1]) do
    table.remove(code, 1)
  end
  return code
end

--- Une las partes con " · " descartando las de menor prioridad (número mayor) hasta que quepa
---@param parts { [1]: string, [2]: integer }[]
---@param width integer
---@return string
local function fit_hint(parts, width)
  local function joined()
    return table.concat(
      vim.tbl_map(function(p)
        return p[1]
      end, parts),
      " · "
    )
  end
  while vim.fn.strdisplaywidth(joined()) > width and #parts > 1 do
    local worst = 1
    for i, p in ipairs(parts) do
      if p[2] >= parts[worst][2] then
        worst = i
      end
    end
    table.remove(parts, worst)
  end
  return joined()
end

---@param job AgentJob
---@param result table
---@return string? summary
function M.done(job, result)
  local code, needs, err, blocks, note = protocol.extract_code(result.text, job.target.lines)
  if not code then
    log.warn("Agent: " .. err .. " (showing the raw response)")
    return require("agent.output.text").done(job, result)
  end
  code = normalize(code, job.target)

  if vim.deep_equal(code, job.target.lines) then
    anchor.delete(job.buf, job.anchor)
    runs.event(job, "unchanged")
    return "no changes"
  end
  if not anchor.unchanged(job) then
    anchor.delete(job.buf, job.anchor)
    runs.event(job, "discarded", "code changed while running")
    log.warn "Agent: the code changed while the agent was working; proposal discarded"
    return nil
  end

  local first = anchor.range(job.buf, job.anchor)
  local proposal = { job = job, lines = code, ids = {} }
  proposal.ids = preview.render(job.buf, first, job.target.lines, code, function(hunks)
    local keys = settings.keys
    -- partes por prioridad (1 = imprescindible): si la ventana es estrecha se descartan las menos
    -- importantes en vez de cortar la línea por la mitad
    local parts = {
      { ("%s accept · %s reject"):format(label(keys.accept), label(keys.reject)), 1 },
      { ("%d change%s"):format(hunks, hunks == 1 and "" or "s"), 2 },
    }
    if blocks and blocks > 1 then
      parts[#parts + 1] = { ("model sent %d blocks, check the diff"):format(blocks), 1 }
    end
    if note then
      parts[#parts + 1] = { "note: " .. note, 1 }
    end
    if needs then
      parts[#parts + 1] = { "import: " .. needs, 2 }
    end
    parts[#parts + 1] = { stats.line(job, result), 3 }
    return fit_hint(parts, vim.api.nvim_win_get_width(0) - 8)
  end)
  proposals[job.buf] = proposals[job.buf] or {}
  table.insert(proposals[job.buf], proposal)
  bind(job.buf)
end

function M.accept()
  local buf = vim.api.nvim_get_current_buf()
  local p = current(buf)
  if not p then
    return
  end
  if not anchor.unchanged(p.job) then
    drop(p)
    runs.event(p.job, "discarded", "code changed since the proposal")
    return log.warn "Agent: the code changed since the proposal; discarded"
  end
  local first, last = anchor.range(buf, p.job.anchor)
  drop(p)
  runs.event(p.job, "accepted")
  -- el código de ese rango se reescribe: lo que el review señalaba ahí ya no aplica (y si era un fix, tampoco
  -- sus violaciones locales de DDD)
  pcall(function()
    require("agent.output.findings").resolve(buf, first, last)
    if p.job.action.fixes then
      require("agent.ddd.diagnose").resolve(buf, first, last)
    end
  end)
  vim.api.nvim_buf_set_lines(buf, first - 1, last, false, p.lines)
  if vim.api.nvim_win_get_buf(0) == buf then
    pcall(vim.api.nvim_win_set_cursor, 0, { first, 0 })
  end

  if settings.apply.format then
    local ok, conform = pcall(require, "conform")
    if ok then
      local end_row = first + #p.lines - 1
      conform.format {
        bufnr = buf,
        async = true,
        quiet = true,
        lsp_format = "fallback",
        range = { start = { first, 0 }, ["end"] = { end_row, #p.lines[#p.lines] } },
      }
    end
  end
end

function M.reject()
  local p = current(vim.api.nvim_get_current_buf())
  if p then
    drop(p)
    runs.event(p.job, "rejected")
  end
end

--- Descarta todas las propuestas pendientes (de un buffer, o de todos)
---@param buf integer?
function M.discard_all(buf)
  for b, list in pairs(proposals) do
    if not buf or b == buf then
      for _, p in ipairs(vim.list_slice(list)) do
        drop(p)
        runs.event(p.job, "discarded", "cleared")
      end
    end
  end
end

---@param job AgentJob
function M.release(job)
  anchor.delete(job.buf, job.anchor)
end

return M
