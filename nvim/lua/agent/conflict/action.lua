-- The action every conflict runs: `fix block` re-framed for a block that holds both sides of a merge. Derived, not
-- registered (the entry points are the Git menu's, `agent.conflict`).
local protocol = require "agent.protocol"

local M = {}

---@return table
function M.build()
  local base = require("agent.actions").get "fix_block"
  return vim.tbl_extend("force", base, {
    name = "conflict_resolve",
    label = "resolve conflict",
    check = nil,
    context = { "rules", "around" },
    system = function()
      return "TASK resolve a git merge conflict. <target> is ONE conflict with its markers: `<<<<<<<` ours, `=======`, `>>>>>>>` theirs, and `|||||||` the common ancestor when the file carries it. <merge> says what each line of work did (commit subjects) and what each changed in this file against the ancestor. Write the merged code that keeps the intent of BOTH sides: when they changed different things, apply both; when they changed the same thing differently, combine them so both behaviours still hold and say how in note. Never drop a side's change silently; if keeping both is impossible, keep ours and say what was lost in note. The result has NO conflict markers and touches nothing outside the conflict. Take names and signatures from <around>.\n"
        .. protocol.REPLACE_RULES
    end,
    task = function()
      return "Resolve the conflict in <target> using <merge>; the result must have no conflict markers."
    end,
  })
end

return M
