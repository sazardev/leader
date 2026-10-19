-- The action an edit step of a diagnosis runs: `fix block` told to apply one described change. Derived, not registered.
local protocol = require "agent.protocol"

local M = {}

---@return table
function M.build()
  local base = require("agent.actions").get "fix_block"
  return vim.tbl_extend("force", base, {
    name = "doctor_fix",
    label = "doctor fix",
    check = nil,
    context = { "rules", "around", "types", "callees" },
    system = function()
      return "TASK apply the change a diagnosis calls for to <target>. <diagnosis> says the root cause and the exact change to make. Make that change and nothing else: no refactor, no restyle, no unrelated fixes. If the change cannot be made in <target> (the file you need is elsewhere), keep <target> valid, change nothing, and say so in note. Never invent values (versions, secrets, hosts); where one is needed, keep the existing one and say so in note. Take names and signatures from <types> and <callees>.\n"
        .. protocol.REPLACE_RULES
    end,
    task = function()
      return "Apply the change described in <diagnosis> to <target>."
    end,
  })
end

return M
