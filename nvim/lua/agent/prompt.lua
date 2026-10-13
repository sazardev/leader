-- ── Prompt assembly ──────────────────────────────────────────────────────────
-- system = the action's role and rules (does not change between calls: it is cached).
-- prompt = <file> + context sections + <target> + <task>, with short tags.
local settings = require("core.settings").agent

local M = {}

local ROLE = [[
Code-editing endpoint in an editor: one narrow task per request, no chat. You see only this message (no tools, no other files); never ask questions; reply only in the requested format.
<rules> are project conventions (obey). <types>, <callees>, <diagnostics> and the file are ground truth: use their exact field, method and API names; never invent members.]]

---@param target AgentTarget
---@param numbered boolean?
---@return string
local function target_block(target, numbered)
  local body = target.lines
  if numbered then
    body = {}
    for i, line in ipairs(target.lines) do
      body[i] = ("%d: %s"):format(target.first + i - 1, line)
    end
  end
  local attrs = ('lines="%d-%d" kind="%s"'):format(target.first, target.last, target.kind)
  if target.name then
    attrs = attrs .. (' name="%s"'):format(target.name)
  end
  return ("<target %s>\n%s\n</target>"):format(attrs, table.concat(body, "\n"))
end

---@param action table
---@param target AgentTarget
---@param sections { name: string, text: string }[]
---@param input string? what the user typed (question, instruction)
---@return string system, string prompt
function M.build(action, target, sections, input)
  local env = { target = target, input = input, language = settings.language }

  local parts = { ('<file path="%s" lang="%s"/>'):format(target.path, target.lang) }
  for _, section in ipairs(sections) do
    parts[#parts + 1] = ("<%s>\n%s\n</%s>"):format(section.name, section.text, section.name)
  end
  parts[#parts + 1] = target_block(target, action.numbered)
  local task = action.task(env)
  if input and action.input_optional then
    -- optional instruction: what the user typed takes priority over the default behaviour
    task = task
      .. "\n\nAdditional instruction from the user (it takes priority over the default behaviour above):\n"
      .. input
  end
  parts[#parts + 1] = ("<task>\n%s\n</task>"):format(task)

  return ROLE .. "\n\n" .. action.system(env), table.concat(parts, "\n")
end

return M
