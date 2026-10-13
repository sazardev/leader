-- Hallazgos del agente que siguen "por atender" dentro del objetivo: los de `review`, `ddd review` y del
-- diagnóstico de DDD. Es lo que lee `fix` para saber QUÉ arreglar. (`diagnostics` no los incluye a propósito:
-- un review nuevo no debe partir de lo que dijo el anterior.)
local persist = require "agent.persist"

local SEVERITY = { "ERROR", "WARN", "INFO", "HINT" }

return {
  cap = 1800,
  ---@param target AgentTarget
  ---@param done fun(text: string?)
  collect = function(target, done)
    local found = {}
    for key, name in pairs(persist.NAMESPACES) do
      for _, d in ipairs(vim.diagnostic.get(target.buf, { namespace = vim.api.nvim_create_namespace(name) })) do
        local line = d.lnum + 1
        if line >= target.first and line <= target.last then
          local code = vim.trim(vim.api.nvim_buf_get_lines(target.buf, d.lnum, d.lnum + 1, false)[1] or "")
          found[#found + 1] = {
            line = line,
            text = ("L%d %s[%s]: %s | %s"):format(
              line,
              SEVERITY[d.severity] or "?",
              d.source or key,
              (d.message or ""):gsub("%s*\n%s*", " "),
              code:sub(1, 100)
            ),
          }
        end
      end
    end
    table.sort(found, function(a, b)
      return a.line < b.line
    end)
    local lines = {}
    for i, f in ipairs(found) do
      if i <= 12 then
        lines[#lines + 1] = f.text
      end
    end
    done(#lines > 0 and table.concat(lines, "\n") or nil)
  end,
}
