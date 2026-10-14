-- The action a retry runs: `fix block` with the framing of a regression. It is derived, not registered: the verifier
-- builds it when it needs it, so the leader menu (generated from the registry) never shows it.
local protocol = require "agent.protocol"

local M = {}

---@param attempt integer
---@param max integer
---@return table
function M.build(attempt, max)
  local base = require("agent.actions").get "fix_block"
  return vim.tbl_extend("force", base, {
    label = ("fix regression %d/%d"):format(attempt, max),
    name = "verify_fix",
    verify = true, -- accepting this one is verified again (up to the retry limit)
    check = nil,
    system = function()
      return "TASK fix a regression: the code in <target> was just changed (a change you or the user accepted) and now has the problems listed in <diagnostics> (and in <verify_errors> when it is given). Resolve them with the smallest change that keeps the INTENT of that change: do not undo it and do not restyle. A problem that is not caused by the change stays as it is. Take member and signature names from <types> and <callees>.\n"
        .. protocol.REPLACE_RULES
    end,
    task = function()
      return "Fix the regression in <target> using <diagnostics> and <verify_errors>."
    end,
  })
end

return M
