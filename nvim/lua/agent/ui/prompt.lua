-- ── Text field for actions with an instruction ───────────────────────────────
-- It is the inline block of ui/inline, above the target code, with the action and the model
-- in the header and that action's history on ↑/↓.
local recall = require "agent.recall"
local inline = require "agent.ui.inline"

local M = {}

---@param action table
---@param target AgentTarget
---@param model_label string
---@param on_submit fun(text: string) with "" if the field was optional and was submitted empty
function M.ask(action, target, model_label, on_submit)
  inline.open({
    win = vim.api.nvim_get_current_win(),
    row = target.first,
    title = action.label,
    meta = action.handler and "Herdr agent" or model_label, -- handing off to Herdr uses no model
    placeholder = action.input_optional and (action.input .. " (Enter to skip)") or action.input,
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
