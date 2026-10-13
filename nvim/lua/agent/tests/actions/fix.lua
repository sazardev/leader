-- Arreglar una prueba que falla: corre la prueba (sin modelo) y solo si falla manda su salida real. Si pasa, 0 tokens.
local convention = require "agent.tests.convention"
local protocol = require "agent.protocol"
local run = require "agent.tests.run"

return {
  label = "test fix",
  desc = "test fix",
  key = "f",
  scope = "function",
  context = { "rules", "types", "callees" },
  output = "replace",
  input = "hint for the fix",
  input_optional = true,
  preparing = "running the test…",
  check = function(target)
    if not convention.is_test_file(vim.api.nvim_buf_get_name(target.buf)) then
      return "put the cursor in a test function (…_test.go, *.test.ts, test_*.py)"
    end
  end,
  ---@param target AgentTarget
  ---@param done fun(extra: table[]?, why: string?)
  prepare = function(target, done)
    local abs = vim.api.nvim_buf_get_name(target.buf)
    local cmd, why = convention.command(abs, target.lang, target.name)
    if not cmd then
      return done(nil, why)
    end
    run.exec(cmd, function(passed, output, err)
      if err then
        return done(nil, err)
      end
      if passed then
        return done(nil, "the test already passes: nothing to fix (0 tokens spent)")
      end
      done { { name = "test_output", text = ("$ %s\n%s"):format(cmd.label, output) } }
    end)
  end,
  system = function()
    return "TASK fix a failing test: <test_output> is the real output of running <target>. Decide the cause first.\n"
      .. "If the TEST is wrong (bad expectation, stale fixture, wrong setup, order or timing dependence), fix the test with the smallest change.\n"
      .. "If the CODE under test is wrong (the test states the correct behaviour), return <target> UNCHANGED and put the bug in `note:`.\n"
      .. "Never weaken an assertion just to go green, never delete a case. Take member and signature names from <types> and <callees>.\n"
      .. protocol.REPLACE_RULES
  end,
  task = function()
    return "Fix <target> using <test_output>."
  end,
}
