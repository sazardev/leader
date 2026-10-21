-- Guard: look at what is about to be sent. Off by default (`settings.agent.trust.preview`); when on, every request
-- (except what a batch already confirmed as a whole) shows its model, what it reads and the start of the message, and
-- asks. For the person who wants to see the prompt before it leaves, and for learning what the context providers add.
local text = require "agent.text"

local M = {}

---@param req table
---@return { level: string, title: string, lines: table }?
function M.check(req)
  if not require("core.settings").agent.trust.preview or req.preapproved or not req.prompt then
    return nil
  end
  local hl = require("utils.modal").hl
  local lines = {
    { { "About to send", hl.warn } },
    { { req.preflight or (req.action .. " · " .. tostring(req.model)), hl.muted } },
    "",
  }
  for _, line in ipairs(vim.split(text.clip(req.prompt, 1600), "\n", { plain = true })) do
    lines[#lines + 1] = { { line, hl.muted } }
  end
  return { level = "confirm", title = "Agent prompt", lines = lines }
end

return M
