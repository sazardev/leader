-- Arreglar EN LÍNEA: el diagnóstico (LSP, linter o hallazgo) de la línea del cursor, y nada más.
-- El objetivo son solo las líneas del diagnóstico; el código de alrededor y los objetos a los que apunta
-- (tipo de la variable, firma de lo llamado) entran como contexto de solo lectura. La versión sobre toda la
-- función es `fix_block`.
local protocol = require "agent.protocol"
local target_mod = require "agent.context.target"

return {
  label = "fix inline",
  desc = "fix inline",
  key = "f",
  scope = "diagnostic",
  context = { "rules", "diagnostics", "findings", "contracts", "around", "types", "callees" },
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
    return "TASK fix inline: resolve ONLY the problem(s) in <diagnostics> and <findings> that sit on the <target> lines, with the smallest possible change (usually just those lines). <around> is the surrounding code: read-only context, never repeat or edit it. A false positive stays unchanged. Take member and signature names from <types> and <callees>. If the real fix lives outside <target> (an import, a missing declaration), keep <target> as valid as you can and say it in needs-import / note.\n"
      .. protocol.REPLACE_RULES
  end,
  task = function()
    return "Fix the problem(s) in <diagnostics> and <findings> on the <target> lines."
  end,
}
