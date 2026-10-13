-- DDD fix: arregla lo que el review de DDD (y el diagnóstico local) dejó por atender, con el cambio mínimo
-- y respetando las capas
local principles = require "agent.ddd.principles"
local protocol = require "agent.protocol"

return {
  label = "ddd fix",
  desc = "ddd fix",
  key = "f",
  scope = "function",
  fixes = true, -- al aceptar, las violaciones locales de ese rango también se dan por resueltas
  context = { "rules", "ddd", "findings", "diagnostics", "contracts", "types" },
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
    return "nothing to fix here: run ddd review (or ddd diagnose) first"
  end,
  system = function()
    return "TASK fix with DDD: resolve every problem listed in <findings> and <diagnostics> with the smallest change that respects the layers in <ddd>. Move logic to the right place only within <target>. If a fix needs a port, type or file that does not exist, make the change that is possible inside <target> and name what else is needed in `note:`; never invent the contents of other files. A false positive stays unchanged.\n"
      .. principles.RULES
      .. "\n"
      .. protocol.REPLACE_RULES
  end,
  task = function()
    return "Fix the problems in <findings> and <diagnostics> inside <target>."
  end,
}
