-- Where the tests go and with which framework (agent/tests/convention.lua). Short on purpose: 2-3 lines.
return {
  cap = 500,
  stability = 1,
  ---@param target AgentTarget the object under test (with `tests`, set by the action)
  ---@param done fun(text: string?)
  collect = function(target, done)
    local info = target.tests
    if not info then
      return done(nil)
    end
    local lines = {
      ("test file: %s (%s)"):format(
        vim.fn.fnamemodify(info.path, ":."),
        info.inline and "inline, same file as the code"
          or info.exists and "exists: append to it"
          or "NEW: write the complete file, including package/imports"
      ),
      "framework: " .. info.framework,
      "style: " .. info.style,
    }
    done(table.concat(lines, "\n"))
  end,
}
