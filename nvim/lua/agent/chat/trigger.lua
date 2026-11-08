-- ── Input triggers (pure) ───────────────────────────────────────────────────
-- Where the cursor is typing `@path`, `#skill`, `$mcp` or a leading `/command`,
-- and how to replace that token with the chosen value. No windows, no timers:
-- the UI (completion.lua) and the tests use the same functions.
local M = {}

M.LABEL = { command = "Commands", file = "Files", skill = "Skills", mcp = "MCP" }
M.SIGN = { command = "/", file = "@", skill = "#", mcp = "$" }
M.TOKEN = "[%w%._%-%/]"

---@param kind string
---@return string
function M.sign(kind)
  return M.SIGN[kind] or "@"
end

---@param kind string
---@return string
function M.label(kind)
  return M.LABEL[kind] or ""
end

--- Token end (0-based, exclusive) from the cursor: consumes the rest of the
--- trigger word so accepting in the middle replaces the WHOLE token.
---@param line string
---@param col integer 0-based byte column of the cursor
---@return integer
function M.token_end(line, col)
  local end_col = col
  while end_col < #line and line:sub(end_col + 1, end_col + 1):match(M.TOKEN) do
    end_col = end_col + 1
  end
  return end_col
end

--- What is being typed at `col` (0-based).
--- `/` only counts as the first thing on the line; `@`, `#`, `$` start a token
--- after whitespace or opening punctuation.
---@param line string
---@param col integer
---@return string? kind, string? query, integer? start_col, integer? end_col
function M.detect(line, col)
  local before = line:sub(1, col)
  local cmd = before:match "^%s*/(%w*)$"
  if cmd then
    local start_col = #before - #cmd - 1 -- 0-based index of the "/"
    return "command", cmd, start_col, M.token_end(line, col)
  end
  local pos, trigger, query = before:match "()([@%#$])([%w%._%-%/]*)$"
  if pos and trigger then
    local prev = pos > 1 and before:sub(pos - 1, pos - 1) or ""
    if prev == "" or prev:match "%s" or prev:match "[%(%[{,;:]" then
      local kind = ({ ["@"] = "file", ["#"] = "skill", ["$"] = "mcp" })[trigger]
      return kind, query, pos - 1, M.token_end(line, col)
    end
  end
  return nil
end

--- The line with the token [start_col, end_col) replaced by `insert`.
---@param line string
---@param start_col integer
---@param end_col integer
---@param insert string
---@return string new_line, integer cursor_col
function M.replace(line, start_col, end_col, insert)
  local new_line = line:sub(1, start_col) .. insert .. line:sub(end_col + 1)
  return new_line, start_col + #insert
end

return M
