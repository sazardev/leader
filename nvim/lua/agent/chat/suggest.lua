-- ── Suggestions for the input triggers (pure) ───────────────────────────────
-- One entry per row of the selector: { value, desc }. Kind decides the source:
-- command → commands.lua · file → files.lua (+ @buf/@sel/@diag) · skill → the
-- installed SKILL.md files · mcp → the servers of the environment.
local commands = require "agent.chat.commands"
local files = require "agent.chat.files"

local M = {}

M.SPECIAL = {
  { value = "buf", desc = "the buffer you are in" },
  { value = "sel", desc = "the visual selection" },
  { value = "diag", desc = "its diagnostics" },
}

---@param kind string
---@param query string?
---@param limit integer?
---@return table[]
function M.all(kind, query, limit)
  query = query or ""
  if kind == "command" then
    return commands.candidates(query)
  elseif kind == "file" then
    local out = {}
    for _, s in ipairs(M.SPECIAL) do
      if query == "" or s.value:find(query, 1, true) == 1 then
        out[#out + 1] = s
      end
    end
    for _, path in ipairs(files.filter(files.list(), query, limit or 50)) do
      out[#out + 1] = { value = path, desc = "" }
    end
    return out
  elseif kind == "skill" then
    local out = {}
    local ok, skills = pcall(require, "skills")
    if ok and skills.list then
      local lower = query:lower()
      for _, s in ipairs(skills.list()) do
        if query == "" or s.id:lower():find(lower, 1, true) == 1 then
          out[#out + 1] = { value = s.id, desc = (s.description or ""):gsub("%s+", " ") }
        end
      end
    end
    return out
  elseif kind == "mcp" then
    local out = {}
    local ok, mention = pcall(require, "agent.chat.mention")
    for _, name in ipairs(ok and mention.mcp_servers() or {}) do
      if query == "" or name:lower():find(query:lower(), 1, true) == 1 then
        out[#out + 1] = { value = name, desc = "MCP server" }
      end
    end
    return out
  end
  return {}
end

return M
