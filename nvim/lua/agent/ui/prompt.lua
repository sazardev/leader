-- ── Campo de texto para acciones con instrucción ─────────────────────────────
-- Es el bloque en línea de ui/inline, encima del código objetivo, con la acción y el modelo
-- en la cabecera y el historial de esa acción en ↑/↓.
local recall = require "agent.recall"
local inline = require "agent.ui.inline"

local M = {}

---@param action table
---@param target AgentTarget
---@param model_label string
---@param on_submit fun(text: string) con "" si el campo era opcional y se envió vacío
function M.ask(action, target, model_label, on_submit)
  inline.open({
    win = vim.api.nvim_get_current_win(),
    row = target.first,
    title = action.label,
    meta = action.handler and "Herdr agent" or model_label, -- entregar a Herdr no usa modelo
    placeholder = action.input_optional and (action.input .. " (⏎ to skip)") or action.input,
    optional = action.input_optional,
    history = recall.list(action.name),
  }, function(text)
    if text ~= "" then
      recall.push(action.name, text)
    end
    on_submit(text)
  end)
end

return M
