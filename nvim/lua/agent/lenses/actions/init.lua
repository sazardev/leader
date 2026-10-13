-- ── Registro de LENTES (<leader>aL) ──────────────────────────────────────────
-- Una lente es una revisión con UN solo foco (seguridad, rendimiento...). Cada archivo declara solo lo que la
-- distingue; aquí se completa el resto (objetivo, salida como diagnósticos, prompt común). Añadir una lente = un
-- archivo + su nombre en NAMES; el menú sale del registro.
--
--   key      string        tecla bajo <leader>aL
--   title    string        nombre corto ("security")
--   focus    string        qué busca (una frase larga: es el prompt)
--   gate     string[]?     palabras: si el código no contiene NINGUNA, la lente ni llama al modelo (0 tokens)
--   context  string[]?     proveedores (por defecto, rules y callees: lo mínimo)
--   tier     string?       "light" = modelo barato; por defecto "main"
--   check    fun(target)?  motivo para no correr (antes de gastar nada)
--
-- Los hallazgos son diagnósticos con su lente como origen (`[security]`): `af`/`aF` los arreglan, y repetir una lente
-- solo reemplaza lo suyo.
local protocol = require "agent.protocol"
local target_mod = require "agent.context.target"

local M = {}

local NAMES = { "security", "performance", "concurrency", "errors", "api" }

---@type table<string, table>
local cache = {}

---@param spec table
---@return table
local function build(spec)
  local action = {
    label = "lens " .. spec.title,
    desc = spec.title,
    key = spec.key,
    source = spec.title,
    scope = "function",
    context = spec.context or { "rules", "callees" },
    output = "findings",
    numbered = true,
    tier = spec.tier,
    check = function(target)
      if spec.gate then
        local text = table.concat(target.lines, "\n"):lower()
        local hit = false
        for _, word in ipairs(spec.gate) do
          if text:find(word, 1, true) then
            hit = true
            break
          end
        end
        if not hit then
          return ("nothing %s-related in the target: skipped (0 tokens)"):format(spec.title)
        end
      end
      return spec.check and spec.check(target) or nil
    end,
    system = function(env)
      return ("TASK %s review (messages in %s): %s\nReport ONLY %s problems; ignore style and every other kind of bug.\n%s"):format(
        spec.title,
        env.language,
        spec.focus,
        spec.title,
        protocol.FINDINGS_RULES
      )
    end,
    task = function()
      return ("Review <target> only for %s problems."):format(spec.title)
    end,
  }
  return action
end

---@param name string
---@return table
function M.get(name)
  if not cache[name] then
    local action = build(require("agent.lenses.actions." .. name))
    action.short = name
    action.name = "lens_" .. name -- `settings.agent.tiers.lens_security = "light"` la reasigna
    cache[name] = action
  end
  return cache[name]
end

---@return table[]
function M.list()
  return vim.tbl_map(M.get, NAMES)
end

M.target = target_mod -- (para pruebas)

return M
