-- Código de ALREDEDOR de un objetivo pequeño (fix inline): lo que hay antes y después dentro de su función,
-- para ver las variables en ámbito y el contrato de retorno sin mandar la función entera como objetivo.
-- Solo lectura: el modelo no lo repite. Si el objetivo ya es la función (o el archivo), no aporta nada.
local settings = require("core.settings").agent.context
local scopes = require "agent.context.scopes"

return {
  cap = 2500,
  ---@param target AgentTarget
  ---@param done fun(text: string?)
  collect = function(target, done)
    if target.kind == "function" or target.kind == "file" or target.kind == "class" then
      return done(nil)
    end
    local total = vim.api.nvim_buf_line_count(target.buf)
    local fn = scopes.enclosing(target.buf, target.first - 1, "function")
    local from = math.max(target.first - settings.around, fn and fn.first or 1)
    local to = math.min(target.last + settings.around, fn and fn.last or total)
    if from >= target.first and to <= target.last then
      return done(nil)
    end
    local function get(a, b)
      return a <= b and vim.api.nvim_buf_get_lines(target.buf, a - 1, b, false) or {}
    end
    local out = {}
    if fn and from > fn.first then
      out[#out + 1] = (get(fn.first, fn.first)[1] or "") .. "   -- (function start)"
      out[#out + 1] = "…"
    elseif from > 1 and not fn then
      out[#out + 1] = "…"
    end
    vim.list_extend(out, get(from, target.first - 1))
    out[#out + 1] = ("[<target> lines %d-%d go here]"):format(target.first, target.last)
    vim.list_extend(out, get(target.last + 1, to))
    if fn and to < fn.last then
      out[#out + 1] = "…"
    end
    done(table.concat(out, "\n"))
  end,
}
