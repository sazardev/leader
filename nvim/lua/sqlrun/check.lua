-- ── Local SQL checks (0 tokens, no process) ───────────────────────────────────
-- The things a database will not tell you until it is too late: a `SELECT *`, a `LIMIT` with no order, a `DELETE`
-- without a WHERE, a join with no condition, a dangling comma. They complement SQLFluff (which is a process and a
-- style checker) and work even with no connection. Pure, so test-langs.lua can check every rule.
local statement = require "sqlrun.statement"

local M = {}

local SEVERITY = vim.diagnostic.severity

---@param text string
---@param dialect string?
---@return table[]
function M.check(text, dialect)
  local lines = vim.split(text or "", "\n", { plain = true })
  local out = {}
  local function add(line, col, severity, message)
    out[#out + 1] = {
      lnum = math.max(line - 1, 0),
      col = math.max(col - 1, 0),
      severity = severity,
      source = "sqlcheck",
      message = message,
    }
  end
  for _, s in ipairs(statement.split(lines)) do
    local t = " " .. s.text:lower():gsub("%s+", " ") .. " "
    local function has(word)
      return t:find("%f[%w]" .. word .. "%f[%W]") ~= nil
    end
    if t:find " select %* " or t:find "^ select %*" then
      add(s.first, 1, SEVERITY.HINT, "SELECT * fetches every column (name them to keep the query stable)")
    end
    if has("update") and not has("where") then
      add(s.first, 1, SEVERITY.WARN, "UPDATE with no WHERE changes every row")
    elseif has("delete") and not has("where") then
      add(s.first, 1, SEVERITY.WARN, "DELETE with no WHERE removes every row")
    end
    if has("limit") and not has("order") then
      add(s.first, 1, SEVERITY.HINT, "LIMIT without ORDER BY returns an arbitrary subset")
    end
    if has("join") and not (has("on") or has("using")) then
      add(s.first, 1, SEVERITY.WARN, "JOIN with no ON/USING makes a cartesian product")
    end
    if dialect == "mysql" or dialect == "mariadb" then
      -- nothing engine-specific yet; the rule list above is shared on purpose
    end
  end
  for row, line in ipairs(lines) do
    local trimmed = line:gsub("%s+$", "")
    if trimmed:match ",$" then
      add(row, #trimmed, SEVERITY.ERROR, "dangling comma at the end of the line")
    else
      local lower = trimmed:lower()
      for _, clause in ipairs { "from", "where", "values" } do
        if lower:find(",%s*" .. clause .. "%f[%W]", 1, false) then
          add(row, #trimmed, SEVERITY.ERROR, "dangling comma before a clause")
          break
        end
      end
    end
  end
  return out
end

return M
