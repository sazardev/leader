-- ── Colores de diagnóstico: una sola fuente para toda la UI ──────────────────
-- La etiqueta de la barra de estado (E2 / W1), el número de línea y los bloques en línea
-- (utils/diagblocks.lua) salen de aquí, así el rojo del error es EL MISMO en los tres sitios.
-- El acento es el `DiagnosticX` del tema activo; el texto sobre él es el fondo del tema (igual
-- que el texto de la sección de modo de lualine) y, si no alcanza contraste, negro o blanco.
local color = require "appearance.color"

local M = {}

local SEV = vim.diagnostic.severity

-- severidad → nombre corto y grupo del tema del que sale el acento
M.KINDS = {
  [SEV.ERROR] = { name = "Error", from = "DiagnosticError", fallback = "#e06c75" },
  [SEV.WARN] = { name = "Warn", from = "DiagnosticWarn", fallback = "#e5c07b" },
  [SEV.INFO] = { name = "Info", from = "DiagnosticInfo", fallback = "#61afef" },
  [SEV.HINT] = { name = "Hint", from = "DiagnosticHint", fallback = "#56b6c2" },
}

---@param name string
---@return integer?
local function fg_of(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false }).fg
end

---@param severity integer
---@return string hex color de acento de esa severidad en el tema activo
function M.accent(severity)
  local kind = M.KINDS[severity]
  local fg = fg_of(kind.from)
  return fg and ("#%06x"):format(fg) or kind.fallback
end

--- Texto legible sobre un fondo de acento (3.5: las etiquetas son en negrita, y así el texto es el
--- mismo en errores y avisos en vez de saltar entre fondo y negro)
---@param accent string
---@return string
function M.on_accent(accent)
  local bg = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
  local base = bg and ("#%06x"):format(bg)
  if base and color.contrast(base, accent) >= 3.5 then
    return base
  end
  return color.contrast("#000000", accent) >= color.contrast("#ffffff", accent) and "#000000" or "#ffffff"
end

--- Etiqueta sólida de la severidad: fondo = acento, texto = `on_accent`, en negrita
---@param severity integer
---@return { bg: string, fg: string, bold: boolean }
function M.pill(severity)
  local accent = M.accent(severity)
  return { bg = accent, fg = M.on_accent(accent), bold = true }
end

-- ── Sincronía con el tema ────────────────────────────────────────────────────
-- Los highlights derivados (número de línea, bloques) se calculan una vez; si el tema cambia sin
-- ColorScheme ni NvThemeReload (base46 carga su caché en silencio al arrancar, el tema heredado de
-- la terminal se recompila en vivo), quedarían con el color anterior mientras la barra de estado,
-- que se evalúa en cada refresco, ya usa el nuevo. `sync()` lo detecta comparando firmas y
-- avisa a quien registró un `on_change`; se llama desde cada refresco de la barra y de los bloques.
local last ---@type string?
local listeners = {} ---@type fun()[]

---@return string
local function signature()
  local parts = { vim.o.background, tostring(vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg) }
  for severity in pairs(M.KINDS) do
    parts[#parts + 1] = M.accent(severity)
  end
  return table.concat(parts, "|")
end

---@param fn fun() recalcula los highlights derivados
function M.on_change(fn)
  listeners[#listeners + 1] = fn
end

--- Si el tema cambió desde la última comprobación, recalcula lo derivado (en el siguiente tick:
--- se puede llamar desde la evaluación de la barra de estado)
function M.sync()
  local current = signature()
  if current == last then
    return
  end
  last = current
  vim.schedule(function()
    for _, fn in ipairs(listeners) do
      fn()
    end
  end)
end

return M
