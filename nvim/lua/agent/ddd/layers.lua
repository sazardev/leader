-- ── Capas de DDD: qué es cada directorio y quién puede depender de quién ─────
local settings = require("core.settings").agent.ddd

local M = {}

--- La regla de dependencia: cada capa solo puede apuntar hacia dentro
M.ALLOWED = {
  domain = { domain = true },
  application = { domain = true, application = true },
  infrastructure = { domain = true, application = true, infrastructure = true },
  interface = { domain = true, application = true, interface = true },
}

M.ORDER = { "domain", "application", "infrastructure", "interface" }

---@type table<string, string>?
local lookup

---@return table<string, string> segmento → capa
local function segments()
  if not lookup then
    lookup = {}
    for layer, names in pairs(settings.layers) do
      for _, name in ipairs(names) do
        lookup[name:lower()] = layer
      end
    end
  end
  return lookup
end

--- La capa de una ruta o de un import: el PRIMER segmento (de izquierda a derecha) que sea un nombre de capa
---@param path string
---@return string?
function M.of(path)
  local map = segments()
  for seg in path:gmatch "[^/\\%.:]+" do
    local layer = map[seg:lower()]
    if layer then
      return layer
    end
  end
  return nil
end

--- ¿El archivo es una raíz de composición (main, cmd/, container...), que puede cablear todas las capas?
---@param rel string ruta relativa a la raíz del proyecto
---@return boolean
function M.is_composition_root(rel)
  local lower = rel:lower()
  for _, root in ipairs(settings.composition_roots) do
    if
      lower:find("^" .. root .. "[/%.]")
      or lower:find("/" .. root .. "[/%.]")
      or lower:match("[/^]" .. root .. "$")
    then
      return true
    end
  end
  return false
end

--- Directorios y archivos que no cuentan para las reglas
---@param rel string
---@return boolean
function M.is_test(rel)
  local lower = rel:lower()
  return lower:find "_test%." ~= nil
    or lower:find "%.test%." ~= nil
    or lower:find "%.spec%." ~= nil
    or lower:find "/tests?/" ~= nil
    or lower:find "^tests?/" ~= nil
    or lower:find "/__tests__/" ~= nil
    or lower:find "/mocks?/" ~= nil
    or lower:find "^test_" ~= nil
    or lower:find "/test_" ~= nil
end

--- Reinicia la caché de nombres (cambió settings.agent.ddd.layers)
function M.reset()
  lookup = nil
end

return M
