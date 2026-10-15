-- The code UNDER TEST, when the result goes to another file (tests, doubles): the target is the end of the
-- destination file, so what must be tested travels separately. No LLM or LSP: only the original target's text.
local scopes = require "agent.context.scopes"
local text = require "agent.text"

local HEADER_MAX = 20

--- Header of the code's file (package/imports/use...): a new test file has to declare the SAME
--- package and know where to import what it tests from
---@param buf integer
---@param first integer first line of the target
---@return string?
local function header(buf, first)
  local decls = scopes.declarations(buf)
  local stop = math.min(decls[1] and decls[1].row or HEADER_MAX, HEADER_MAX, first - 1)
  local lines = vim.tbl_filter(function(l)
    return l:match "%S"
  end, vim.api.nvim_buf_get_lines(buf, 0, stop, false))
  return #lines > 0 and table.concat(lines, "\n") or nil
end

return {
  cap = 3500,
  stability = 3,
  ---@param target AgentTarget the object under test
  ---@param done fun(text: string?)
  collect = function(target, done)
    if not target.tests then
      return done(nil)
    end
    local head = header(target.buf, target.first)
    local body = table.concat(target.lines, "\n")
    if head then
      body = "-- file header (the test file must use the same package/module):\n"
        .. head
        .. "\n-- the code under test:\n"
        .. body
    end
    done(text.clip(("-- %s:%d-%d\n%s"):format(target.path, target.first, target.last, body), 3500))
  end,
}
