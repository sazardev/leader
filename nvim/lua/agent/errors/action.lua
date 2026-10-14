-- The action "fix from output" runs for each piece: `fix block` with the framing of errors printed by a tool. Derived, not
-- registered (the registered one, `errors`, is the standalone entry that gathers and groups them).
local protocol = require "agent.protocol"

local M = {}

---@param label string
---@return table
function M.build(label)
  local base = require("agent.actions").get "fix_block"
  return vim.tbl_extend("force", base, {
    name = "errors_fix",
    label = label,
    check = nil,
    system = function()
      return "TASK fix the errors a tool printed for this code: <build_errors> are lines from a compiler, linter or test runner (file line:col message) that fall inside <target>. Resolve each with the smallest change; errors that share a cause are fixed together. If the real cause is outside <target> (a missing import, a declaration elsewhere), keep <target> as valid as you can and say so in needs-import / note. An error that is not about this code stays as it is. Take member and signature names from <types> and <callees>.\n"
        .. protocol.REPLACE_RULES
    end,
    task = function()
      return "Fix the errors in <build_errors> that point into <target>."
    end,
  })
end

--- The section sent with a piece: its own errors only, one line each (line:col message)
---@param diags table[] diagnostic-like (lnum 0-based)
---@param source string? where they came from ("go build ./...")
---@return { name: string, text: string }[]
function M.section(diags, source)
  local lines = {}
  if source and source ~= "" then
    lines[#lines + 1] = "$ " .. source
  end
  for _, d in ipairs(diags) do
    lines[#lines + 1] = ("%d:%d %s"):format(d.lnum + 1, (d.col or 0) + 1, (d.message or ""):gsub("\n.*", ""))
  end
  return { { name = "build_errors", text = table.concat(lines, "\n") } }
end

return M
