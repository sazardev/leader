-- ── Where the errors come from ───────────────────────────────────────────────
-- Three places a failing build leaves its errors, tried in this order by "fix from output": the last terminal (the build
-- you just ran by hand), the quickfix list (`:make`, a grep, another plugin), or a command we run ourselves. Each returns
-- text or errors; none of them talks to a model.
local parse = require "agent.errors.parse"

local M = {}

--- The text of the most recently used terminal buffer (the last `max_lines` lines), colors stripped
---@param max_lines integer
---@return string?
function M.terminal(max_lines)
  local best
  for _, info in ipairs(vim.fn.getbufinfo { bufloaded = 1 }) do
    if vim.bo[info.bufnr].buftype == "terminal" and (not best or info.lastused > best.lastused) then
      best = info
    end
  end
  if not best then
    return nil
  end
  local count = vim.api.nvim_buf_line_count(best.bufnr)
  local lines = vim.api.nvim_buf_get_lines(best.bufnr, math.max(0, count - max_lines), count, false)
  local text = parse.strip_ansi(table.concat(lines, "\n"))
  return vim.trim(text) ~= "" and text or nil
end

--- Runs `run` ({ cmd, cwd, label }) and hands back everything it printed
---@param run { cmd: string[], cwd: string, label: string }
---@param cb fun(text: string?, err: string?)
function M.command(run, cb)
  require("agent.tests.run").exec(run, function(_, output, err)
    cb(err == nil and output or nil, err)
  end, { raw = true })
end

--- The first source that has errors for this project: terminal, then quickfix
---@param root string
---@param opts { terminal_lines: integer }
---@return AgentToolError[] errors, string? label which source they came from
function M.auto(root, opts)
  local text = M.terminal(opts.terminal_lines)
  if text and parse.looks_like_errors(text) then
    local errors = parse.parse(text, { root = root })
    if #errors > 0 then
      return errors, "the last terminal"
    end
  end
  local errors = parse.from_quickfix { root = root }
  if #errors > 0 then
    return errors, "the quickfix list"
  end
  return {}, nil
end

return M
