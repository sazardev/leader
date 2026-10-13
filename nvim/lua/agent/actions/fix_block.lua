-- Arreglar el BLOQUE: todos los diagnósticos de la función (o de la selección) a la vez, con el cambio
-- mínimo que deja el bloque coherente (una misma causa puede tocar varias líneas). El nivel de una sola
-- línea es `fix`.
local protocol = require "agent.protocol"
local target_mod = require "agent.context.target"

return {
  label = "fix block",
  desc = "fix block",
  key = "F",
  scope = "function",
  context = { "rules", "diagnostics", "findings", "contracts", "types", "callees" },
  fixes = true,
  output = "replace",
  input = "hint for the fix",
  input_optional = true,
  ---@param target AgentTarget
  check = function(target)
    if not target_mod.has_diagnostics(target) then
      return "no diagnostics in the target: nothing to fix"
    end
  end,
  system = function()
    return "TASK fix block: resolve every problem in <diagnostics> and <findings> (what a review flagged) inside <target>, with the smallest change that keeps the whole block coherent: problems that share a root cause are fixed together; no refactor or restyle. A false positive stays unchanged. Take member and signature names from <types> and <callees>.\n"
      .. protocol.REPLACE_RULES
  end,
  task = function()
    return "Fix the problems in <diagnostics> and <findings> inside <target>."
  end,
}
