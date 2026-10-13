-- Arreglar: solo los diagnósticos del LSP que hay dentro del objetivo, con el cambio mínimo
local protocol = require "agent.protocol"

return {
  label = "fix",
  desc = "fix",
  key = "f",
  scope = "function",
  context = { "rules", "diagnostics", "findings", "contracts", "types", "callees" },
  fixes = true,
  output = "replace",
  input = "hint for the fix",
  input_optional = true,
  ---@param target AgentTarget
  check = function(target)
    for _, d in ipairs(vim.diagnostic.get(target.buf)) do
      local line = d.lnum + 1
      if line >= target.first and line <= target.last then
        return nil
      end
    end
    return "no diagnostics in the target: nothing to fix"
  end,
  system = function()
    return "TASK fix: resolve every problem in <diagnostics> and <findings> (what a review flagged) with the smallest change; no refactor or restyle. A false positive stays unchanged. Take member names from <types>.\n"
      .. protocol.REPLACE_RULES
  end,
  task = function()
    return "Fix the problems in <diagnostics> and <findings> inside <target>."
  end,
}
