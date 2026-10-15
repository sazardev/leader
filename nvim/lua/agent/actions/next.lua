-- Next edit, on demand: from what you just changed, the edit you are about to make in the code around the cursor. One key
-- press and a light model (a small local one is enough), not a stream of ghost text. Nothing to learn from = no request.
local edits = require "agent.edits"
local protocol = require "agent.protocol"

return {
  label = "next edit",
  desc = "next edit",
  key = "n",
  scope = "window",
  context = { "rules", "edits" },
  output = "replace",
  tier = "light", -- a small, fast model: the pattern is in <edits>, little reasoning needed
  ---@param target AgentTarget
  check = function(target)
    if #edits.get(target.buf) == 0 then
      return "no recent edits in this file to learn from: change something first"
    end
  end,
  system = function()
    return "TASK next edit: <edits> are the user's latest changes in this file, oldest first (`-` removed, `+` added, `@@ line` = where). Predict the ONE edit they are about to make next inside <target>: the same change applied where it is still missing, the follow-through of a rename or a new field or parameter, the next case of a pattern they started. Apply only that edit, as small as it can be, and keep everything else byte-identical. If nothing in <target> clearly follows from <edits>, return <target> unchanged and say so in note.\n"
      .. protocol.REPLACE_RULES
  end,
  task = function()
    return "Make the next edit that <edits> imply inside <target>."
  end,
}
