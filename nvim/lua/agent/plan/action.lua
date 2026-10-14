-- The action every step of a plan runs: `refactor` told that it is ONE step of a bigger change. Derived, not registered.
local protocol = require "agent.protocol"

local M = {}

---@return table
function M.build()
  local base = require("agent.actions").get "refactor"
  return vim.tbl_extend("force", base, {
    name = "plan_step",
    label = "plan",
    context = { "rules", "types", "callees", "outline" },
    input = nil,
    input_optional = true, -- the step's text is appended as the instruction that wins
    system = function()
      return "TASK apply ONE step of a multi-file plan to <target>: <plan> gives the overall change and marks which step is this one; <earlier_steps> are the proposals already made for the steps before it (assume they will be accepted: use the names and signatures they introduce). Change <target> to do this step and nothing else; keep everything the step does not touch. Take member and signature names from <types> and <callees>.\n"
        .. protocol.REPLACE_RULES
    end,
    task = function()
      return "Apply the step marked as THIS STEP in <plan> to <target>."
    end,
  })
end

return M
