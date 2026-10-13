-- ── Ancla del objetivo ───────────────────────────────────────────────────────
-- Un extmark que cubre las líneas del objetivo: si mientras el agente trabaja editas
-- por encima, el rango se desplaza solo. Al aplicar un resultado se comprueba además
-- que el texto siga siendo el que se envió (si no, se descarta en vez de pisarlo).
local M = {}

local NS = vim.api.nvim_create_namespace "agent.anchor"

--- Final del rango como posición de extmark: SIEMPRE (última línea, fin de esa línea).
--- La forma "(línea siguiente, col 0)" fallaría para un objetivo que acaba en la última
--- línea del buffer: nvim recorta ese extremo y el rango se colapsaría a una fila.
---@param buf integer
---@param last integer 1-based, inclusivo
---@return integer end_row, integer end_col
function M.finish(buf, last)
  local line = vim.api.nvim_buf_get_lines(buf, last - 1, last, false)[1] or ""
  return last - 1, #line
end

--- Final para PINTAR un rango: (línea siguiente, col 0) incluye el salto de línea, así que
--- `hl_eol` también cubre la última fila; solo en la última línea del buffer no existe "la
--- siguiente" y se cae a (última, fin). Es solo visual: la lógica usa `finish`.
---@param buf integer
---@param last integer 1-based, inclusivo
---@return integer end_row, integer end_col
function M.highlight_end(buf, last)
  if last < vim.api.nvim_buf_line_count(buf) then
    return last, 0
  end
  return M.finish(buf, last)
end

---@param buf integer
---@param first integer 1-based
---@param last integer 1-based, inclusivo
---@return integer id
function M.create(buf, first, last)
  local end_row, end_col = M.finish(buf, last)
  return vim.api.nvim_buf_set_extmark(buf, NS, first - 1, 0, {
    end_row = end_row,
    end_col = end_col,
    right_gravity = false,
    end_right_gravity = false,
    invalidate = true,
    strict = false,
  })
end

--- Rango actual (1-based, inclusivo); nil si el texto del ancla se borró
---@param buf integer
---@param id integer
---@return integer?, integer?
function M.range(buf, id)
  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end
  local mark = vim.api.nvim_buf_get_extmark_by_id(buf, NS, id, { details = true })
  local details = mark[3]
  if not details or details.invalid then
    return nil
  end
  return mark[1] + 1, details.end_row + 1
end

--- ¿El texto bajo el ancla sigue siendo el que se envió?
---@param job table
---@return boolean
function M.unchanged(job)
  local first, last = M.range(job.buf, job.anchor)
  if not first then
    return false
  end
  return vim.deep_equal(vim.api.nvim_buf_get_lines(job.buf, first - 1, last, false), job.target.lines)
end

---@param buf integer
---@param id integer
function M.delete(buf, id)
  if vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_del_extmark, buf, NS, id)
  end
end

return M
