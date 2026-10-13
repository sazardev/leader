-- Rules: conventions the model must follow (global setting + the project's `.agent.md`)
local settings = require("core.settings").agent
local project = require "utils.project"

return {
  cap = 1500,
  ---@param target AgentTarget
  ---@param done fun(text: string?)
  collect = function(target, done)
    local parts = {}
    if settings.rules then
      parts[#parts + 1] = settings.rules
    end
    local root = vim.fs.root(target.buf, ".agent.md")
    local file = root and project.read(root .. "/.agent.md")
    if file then
      parts[#parts + 1] = file
    end
    done(#parts > 0 and table.concat(parts, "\n") or nil)
  end,
}
