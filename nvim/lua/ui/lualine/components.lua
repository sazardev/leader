-- ── Componentes de lualine ───────────────────────────────────────────────────
local M = {}

-- ── Diagnósticos ─────────────────────────────────────────────────────────────
-- Errores y warnings por separado (el uno nunca tapa al otro), como etiquetas sólidas con el
-- color de la severidad. Solo cuentan; el detalle está en el código. Los colores salen de
-- ui/diagcolors.lua, los mismos del número de línea y de los bloques en línea.
local SEVERITY = vim.diagnostic.severity
local LETTER = { [SEVERITY.ERROR] = "E", [SEVERITY.WARN] = "W" }

---@param severity integer
---@return table color de lualine: fondo = acento de la severidad, texto legible encima
local function pill_color(severity)
  local diag = require "ui.diagcolors"
  diag.sync() -- si el tema cambió, el número de línea y los bloques se recalculan con esta barra
  local pill = diag.pill(severity)
  return { fg = pill.fg, bg = pill.bg, gui = "bold" }
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

-- ── Agente ───────────────────────────────────────────────────────────────────
--- Spinner mientras hay acciones del agente en marcha. No carga el agente: si nunca se usó
--- (módulo sin cargar) no hay nada que mostrar.
---@return table componente de lualine
function M.agent_status()
  return {
    function()
      local jobs = package.loaded["agent.jobs"]
      return jobs and jobs.statusline() or ""
    end,
    cond = function()
      local jobs = package.loaded["agent.jobs"]
      return jobs ~= nil and #jobs.running() > 0
    end,
    color = "AgentStatus",
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
