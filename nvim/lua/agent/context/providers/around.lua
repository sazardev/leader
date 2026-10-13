-- Code AROUND a small target (inline fix): what comes before and after inside its function,
-- to see the variables in scope and the return contract without sending the whole function as the target.
-- Read-only: the model does not repeat it. If the target is already the function (or the file), it contributes nothing.
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
