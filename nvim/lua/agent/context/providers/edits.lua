-- Your latest changes in this file (old → new lines), oldest first: what "next edit" reads to see which pattern you are in the
-- middle of. Local and free; with nothing changed it contributes nothing.
local edits = require "agent.edits"
local settings = require("core.settings").agent.next_edit

return {
  cap = settings.max_chars,
  stability = 3,
  ---@param target AgentTarget
  ---@param done fun(text: string?)
  collect = function(target, done)
    local list = edits.get(target.buf)
    done(#list > 0 and edits.render(list, settings.max_chars) or nil)
  end,
}
