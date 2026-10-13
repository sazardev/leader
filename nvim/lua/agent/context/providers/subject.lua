-- El código BAJO PRUEBA, cuando el resultado va a otro archivo (pruebas, dobles): el objetivo es el final del
-- archivo de destino, así que lo que hay que probar viaja aparte. Sin LLM ni LSP: solo el texto del objetivo original.
local scopes = require "agent.context.scopes"
local text = require "agent.text"

local HEADER_MAX = 20

--- Cabecera del archivo del código (package/imports/use...): un archivo de pruebas nuevo tiene que declarar el MISMO
--- paquete y saber de dónde importar lo que prueba
---@param buf integer
---@param first integer primera línea del objetivo
---@return string?
local function header(buf, first)
  local decls = scopes.declarations(buf)
  local stop = math.min(decls[1] and decls[1].row or HEADER_MAX, HEADER_MAX, first - 1)
  local lines = vim.tbl_filter(function(l)
    return l:match "%S"
  end, vim.api.nvim_buf_get_lines(buf, 0, stop, false))
  return #lines > 0 and table.concat(lines, "\n") or nil
end

return {
  cap = 3500,
  ---@param target AgentTarget el objeto bajo prueba
  ---@param done fun(text: string?)
  collect = function(target, done)
    if not target.tests then
      return done(nil)
    end
    local head = header(target.buf, target.first)
    local body = table.concat(target.lines, "\n")
    if head then
      body = "-- file header (the test file must use the same package/module):\n"
        .. head
        .. "\n-- the code under test:\n"
        .. body
    end
    done(text.clip(("-- %s:%d-%d\n%s"):format(target.path, target.first, target.last, body), 3500))
  end,
}
