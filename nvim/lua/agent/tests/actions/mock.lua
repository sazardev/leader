-- Doble de prueba: un fake escrito a mano para la interfaz/clase bajo el cursor, añadido al archivo de pruebas.
local protocol = require "agent.protocol"
local dest = require "agent.tests.target"

return {
  label = "test mock",
  desc = "test mock",
  key = "m",
  scope = "type",
  tier = "light", -- es mecánico (firmas → fake): modelo ligero
  context = { "rules", "testing", "subject", "types", "testfile" },
  output = "replace",
  reveal = true,
  retarget = dest.retarget,
  merge = dest.merge,
  check = function(subject)
    return require("agent.tests.convention").is_test_file(vim.api.nvim_buf_get_name(subject.buf))
        and "this is already a test file"
      or nil
  end,
  system = function()
    return "TASK write a test double for <subject> (an interface, port or class). <target> is the END of the test file described in <testing>: output ONLY the new code to append.\n"
      .. "A hand-written fake that implements EVERY method of <subject> with its exact signature: it records each call's arguments and returns values or errors the test sets up. Name it after the type (fakeX / FakeX / MockX per <testfile> style). Where the language allows, add a compile-time check that it satisfies the interface.\n"
      .. "Use the framework mocking tools only when <testing> shows they are the project's convention; otherwise hand-written. Do not write tests, only the double. Do not duplicate one that <testfile> already has.\n"
      .. protocol.APPEND_RULES
  end,
  task = function()
    return "Write the test double for <subject>."
  end,
}
