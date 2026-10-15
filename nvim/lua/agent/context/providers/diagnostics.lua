-- LSP/linter diagnostics inside the target (not the ones the agent itself generated)
local SEVERITY = { "ERROR", "WARN", "INFO", "HINT" }

return {
  cap = 1500,
  stability = 3,
  ---@param target AgentTarget
  ---@param done fun(text: string?)
  collect = function(target, done)
    local agent_ns = require("agent.output.findings").namespace()
    local lines = {}
    for _, d in ipairs(vim.diagnostic.get(target.buf)) do
      local line = d.lnum + 1
      if d.namespace ~= agent_ns and line >= target.first and line <= target.last then
        local msg = (d.message or ""):gsub("%s*\n%s*", " ")
        -- the target is not numbered: without the line's text, "L16" cannot be located
        local code = vim.trim(vim.api.nvim_buf_get_lines(target.buf, d.lnum, d.lnum + 1, false)[1] or "")
        lines[#lines + 1] = ("L%d %s: %s%s | %s"):format(
          line,
          SEVERITY[d.severity] or "?",
          msg,
          d.source and (" [" .. d.source .. "]") or "",
          code:sub(1, 100)
        )
        if #lines >= 12 then
          break
        end
      end
    end
    done(#lines > 0 and table.concat(lines, "\n") or nil)
  end,
}
