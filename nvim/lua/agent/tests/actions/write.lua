-- Escribir pruebas: para la función bajo el cursor (o la selección), SOLO lo que falta, añadido al archivo de pruebas.
local protocol = require "agent.protocol"
local dest = require "agent.tests.target"

return {
  label = "test write",
  desc = "test write",
  key = "w",
  scope = "function",
  -- subject = lo que se prueba; testfile = cabecera, nombres y un ejemplo del archivo de pruebas (no entero)
  context = { "rules", "testing", "subject", "types", "callees", "testfile" },
  output = "replace",
  reveal = true,
  retarget = dest.retarget,
  merge = dest.merge,
  check = dest.check,
  input = "what to cover?",
  input_optional = true,
  system = function()
    return "TASK write tests for <subject> (the code under test). <target> is the END of the test file described in <testing>: output ONLY new test code to append.\n"
      .. "Match <testfile> (imports, helpers, naming, style) and never repeat a case it already has; when it lists existing tests for this code, add only what is missing.\n"
      .. "Cover: the main path, boundaries (empty, zero, nil/null, max) and every error branch visible in <subject>: one case per distinct branch, at most 6, table-driven where the language idiom allows.\n"
      .. "Be minimal: no unused helpers, fields or counters, no comments, no case that only repeats another. Fake only what crosses a boundary (I/O, network, clock, randomness), with the smallest possible fake. Use exact names and signatures from <types> and <callees>. Deterministic: no sleeps, no network. Assert behaviour, not implementation. A NEW test file declares the SAME package/module as <subject>'s file header, plus its imports.\n"
      .. protocol.APPEND_RULES
  end,
  task = function()
    return "Write the missing tests for <subject>."
  end,
}
