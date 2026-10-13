-- ── Registro de acciones ─────────────────────────────────────────────────────
-- Una acción = una receta fija: qué objetivo toma, qué contexto pide, qué prompt
-- lleva y cómo se presenta el resultado. Contrato (campos de cada archivo):
--
--   label      string        nombre corto (estado, títulos)
--   desc       string        texto del menú del leader
--   key        string        tecla bajo <leader>a
--   modes      string[]?     modos del mapeo (por defecto n y x)
--   scope      string        "function" | "class" | "type" | "file" | "lines" (la selección visual manda;
--                            "type" = el tipo bajo el cursor, o el de su receptor si estás en un método de Go)
--   context    string[]?     proveedores de agent/context/providers
--   output     string        presentador: "replace" | "findings" | "text" (agent/output)
--   numbered   boolean?      numerar las líneas del objetivo (hallazgos por línea)
--   input      string?       si abre el campo de instrucción en línea: el placeholder del campo
--   input_optional boolean?  con `input`: Enter con el campo vacío corre sin instrucción (implement, docs,
--              fix); sin esto el texto es obligatorio (ask, refactor, handoff)
--   enabled    fun(): boolean?  si devuelve false la acción no aparece en el menú (handoff fuera de Herdr)
--   examples   boolean?      pide a los proveedores un ejemplo de estilo del propio proyecto (contracts)
--   tier       string?       "light" = corre en el modelo ligero (barato); por defecto "main"
--   system(env), task(env)   prompts; env = { target, input, language }
--   check(target)            (opcional) devuelve un error si la acción no aplica aquí
--   handler(session)         (opcional) sustituye todo el flujo del modelo (p. ej. handoff)
--
-- Añadir una acción: crea `agent/actions/<nombre>.lua` y agrégala a NAMES; el menú y
-- el cheatsheet salen solos.
local M = {}

local NAMES = { "implement", "review", "explain", "ask", "fix", "docs", "refactor", "handoff" }

---@type table<string, table>
local cache = {}

---@param name string
---@return table
function M.get(name)
  if not cache[name] then
    local action = require("agent.actions." .. name)
    action.name = name
    cache[name] = action
  end
  return cache[name]
end

---@return table[]
function M.list()
  return vim.tbl_map(M.get, NAMES)
end

return M
