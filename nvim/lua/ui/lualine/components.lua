-- ── Componentes de lualine ───────────────────────────────────────────────────
local M = {}

-- ── Diagnósticos ─────────────────────────────────────────────────────────────
-- Errores y warnings por separado (el uno nunca tapa al otro), como etiquetas con el
-- color de la severidad de fondo y texto negro. Solo cuentan; el detalle está en el código.
local SEVERITY = vim.diagnostic.severity
local FALLBACK = { [SEVERITY.ERROR] = "#e06c75", [SEVERITY.WARN] = "#e5c07b" }
local HL = { [SEVERITY.ERROR] = "DiagnosticError", [SEVERITY.WARN] = "DiagnosticWarn" }
local LETTER = { [SEVERITY.ERROR] = "E", [SEVERITY.WARN] = "W" }

---@param severity integer
---@return table color de lualine: fondo = color del tema para esa severidad, texto negro
local function pill_color(severity)
  local fg = vim.api.nvim_get_hl(0, { name = HL[severity], link = false }).fg
  return { fg = "#000000", bg = fg and ("#%06x"):format(fg) or FALLBACK[severity], gui = "bold" }
end

--- Etiqueta " E2 " / " W1 " (vacía si no hay de esa severidad; `cond` la oculta)
---@param severity integer
---@return table componente de lualine
function M.diagnostic_count(severity)
  return {
    function()
      return (" %s%d "):format(LETTER[severity], vim.diagnostic.count(0)[severity] or 0)
    end,
    cond = function()
      return (vim.diagnostic.count(0)[severity] or 0) > 0
    end,
    color = function()
      return pill_color(severity)
    end,
    padding = 0,
  }
end

---@return string nombre de la carpeta de trabajo
function M.project_name()
  local cwd = vim.uv.cwd() or ""
  return cwd:match "([^/\\]+)[/\\]*$" or cwd
end

---@return boolean
function M.is_wide()
  return vim.o.columns > 85
end

return M
