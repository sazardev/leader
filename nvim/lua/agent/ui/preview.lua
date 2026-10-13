-- ── Vista previa de un reemplazo, en línea ───────────────────────────────────
-- Lo borrado se tiñe de rojo en su sitio; lo añadido aparece en verde justo debajo,
-- como líneas virtuales (no existen en el buffer hasta que aceptes). Solo se pintan
-- los tramos que cambian, no todo el bloque.
local diff = require "agent.output.diff"

require("agent.ui.highlights").ensure()

local M = {}

local NS = vim.api.nvim_create_namespace "agent.preview"

--- Las líneas virtuales no expanden tabs: se hace a mano, y se rellena hasta el borde
---@param buf integer
---@param line string
---@param width integer
---@return string
local function virtual_line(buf, line, width)
  local text = line:gsub("\t", (" "):rep(vim.bo[buf].tabstop))
  local pad = width - vim.fn.strdisplaywidth(text)
  return pad > 0 and text .. (" "):rep(pad) or text
end

---@param buf integer
---@param first integer 1-based, inicio del bloque viejo
---@param old string[]
---@param new string[]
---@param hint string|fun(hunks: integer): string texto a la derecha de la primera línea
---@return integer[] ids  extmarks creados (para limpiar)
---@return integer hunks  cuántos tramos cambian
function M.render(buf, first, old, new, hint)
  local ids = {}
  local width = vim.o.columns
  local hunks = diff.hunks(old, new)

  local function mark(row, opts)
    opts.strict = false
    ids[#ids + 1] = vim.api.nvim_buf_set_extmark(buf, NS, row, 0, opts)
  end

  for _, h in ipairs(hunks) do
    -- fila (0-based) de la línea vieja `i` (1-based dentro del bloque)
    local function row_of(i)
      return first - 2 + i
    end

    for i = h.a_start, h.a_start + h.a_count - 1 do
      mark(row_of(i), { line_hl_group = "AgentDiffDelete" })
    end

    if h.b_count > 0 then
      local virt = {}
      for j = h.b_start, h.b_start + h.b_count - 1 do
        virt[#virt + 1] = { { virtual_line(buf, new[j], width), "AgentDiffAdd" } }
      end
      if h.a_count > 0 then
        mark(row_of(h.a_start + h.a_count - 1), { virt_lines = virt })
      elseif h.a_start == 0 then
        mark(first - 1, { virt_lines = virt, virt_lines_above = true })
      else
        mark(row_of(h.a_start), { virt_lines = virt })
      end
    end
  end

  local label = type(hint) == "function" and hint(#hunks) or hint
  -- la pista va en su propia línea virtual encima: a la derecha taparía código
  mark(first - 1, { virt_lines = { { { " " .. label, "AgentHint" } } }, virt_lines_above = true })
  return ids, #hunks
end

---@param buf integer
---@param ids integer[]
function M.clear(buf, ids)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  for _, id in ipairs(ids) do
    pcall(vim.api.nvim_buf_del_extmark, buf, NS, id)
  end
end

return M
