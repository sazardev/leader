-- ── The plan prompt ──────────────────────────────────────────────────────────
-- Instruction + the sites (signatures only, never bodies) + the format. Pure: sites in, text out.
local protocol = require "agent.protocol"

local M = {}

M.SYSTEM = table.concat({
  "Plan a code change that spans several files. You see only the instruction and the declarations listed in <sites> (path, line, first line of each function or type): not their bodies.",
  "Decide which of those declarations must change for the instruction to be done everywhere it reaches, and what each change is. Do not invent files or symbols that are not listed.",
  protocol.PLAN_RULES,
}, "\n")

---@param instruction string
---@param seed { name: string?, kind: string, path: string }
---@param sites AgentPlanSite[]
---@return string
function M.build(instruction, seed, sites)
  local lines = {}
  local last_path
  for _, s in ipairs(sites) do
    if s.path ~= last_path then
      lines[#lines + 1] = s.path .. (s.test and "  (test)" or "")
      last_path = s.path
    end
    lines[#lines + 1] = ("  L%d %s%s"):format(s.first, s.signature, s.seed and "   <- starts here" or "")
  end
  return table.concat({
    ("<instruction>\n%s\n</instruction>"):format(instruction),
    ("<seed>%s %s in %s</seed>"):format(seed.kind, seed.name or "?", seed.path),
    ("<sites>\n%s\n</sites>"):format(table.concat(lines, "\n")),
  }, "\n")
end

--- Keeps the steps that name a declaration that really is in the sites (the model inventing a file or a function is dropped),
--- each once, in the order given, numbered again
---@param steps { n: integer, path: string, symbol: string, what: string }[]
---@param sites AgentPlanSite[]
---@return { n: integer, path: string, symbol: string, what: string, site: AgentPlanSite, on: boolean }[]
function M.validate(steps, sites)
  local out, seen = {}, {}
  for _, step in ipairs(steps) do
    local found
    for _, s in ipairs(sites) do
      if s.path == step.path and s.name == step.symbol then
        found = s
        break
      end
    end
    local key = step.path .. "\0" .. step.symbol
    if found and not seen[key] then
      seen[key] = true
      out[#out + 1] =
        { n = #out + 1, path = step.path, symbol = step.symbol, what = step.what, site = found, on = true }
    end
  end
  return out
end

return M
