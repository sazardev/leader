-- Dónde van las pruebas y con qué framework (agent/tests/convention.lua). Corto a propósito: 2-3 líneas.
return {
  cap = 500,
  ---@param target AgentTarget el objeto bajo prueba (con `tests`, que puso la acción)
  ---@param done fun(text: string?)
  collect = function(target, done)
    local info = target.tests
    if not info then
      return done(nil)
    end
    local lines = {
      ("test file: %s (%s)"):format(
        vim.fn.fnamemodify(info.path, ":."),
        info.inline and "inline, same file as the code"
          or info.exists and "exists: append to it"
          or "NEW: write the complete file, including package/imports"
      ),
      "framework: " .. info.framework,
      "style: " .. info.style,
    }
    done(table.concat(lines, "\n"))
  end,
}
