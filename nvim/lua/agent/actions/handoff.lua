-- Hand off: sends file:range + your instruction to an agent already running in Herdr
local log = require "utils.log"

---@param target AgentTarget
---@param instruction string
---@return string
local function message(target, instruction)
  local target_mod = require "agent.context.target"
  local lines = {
    instruction,
    "",
    ("Context: %s:%d-%d (%s)"):format(target.path, target.first, target.last, target_mod.describe(target)),
  }
  local diags = {}
  for _, d in ipairs(vim.diagnostic.get(target.buf)) do
    local line = d.lnum + 1
    if line >= target.first and line <= target.last then
      diags[#diags + 1] = ("  L%d: %s"):format(line, (d.message or ""):gsub("%s*\n%s*", " "))
    end
  end
  if #diags > 0 then
    lines[#lines + 1] = "Diagnostics:"
    vim.list_extend(lines, diags)
  end
  -- the agent reads the file from disk: if there are unsaved changes, the current code is sent
  if vim.bo[target.buf].modified then
    lines[#lines + 1] = "The file has unsaved changes; this is the current code of the range:"
    lines[#lines + 1] = "```" .. target.lang
    vim.list_extend(lines, target.lines)
    lines[#lines + 1] = "```"
  end
  return table.concat(lines, "\n")
end

return {
  label = "handoff",
  desc = "hand off",
  key = "g",
  enabled = function() -- only makes sense inside Herdr: outside it, it does not even show up in the menu
    return require("herdr").inside()
  end,
  scope = "function",
  input = "instruction for the agent",
  ---@param session { target: AgentTarget, input: string }
  handler = function(session)
    local herdr = require "agent.handoff.herdr"
    if not herdr.available() then
      return log.warn "Agent: handoff requires running inside Herdr (HERDR_ENV=1)"
    end
    herdr.agents(function(agents)
      if #agents == 0 then
        return log.warn "Agent: there are no Herdr agents to hand off to"
      end
      local items = vim.tbl_map(function(a)
        return { label = herdr.label(a), pane_id = a.pane_id }
      end, agents)
      require("agent.ui.select").pick(items, { title = "Agent · hand off to" }, function(choice)
        herdr.send(choice.pane_id, message(session.target, session.input), function(ok, err)
          if ok then
            log.info("Agent: sent to " .. choice.label)
          else
            log.error("Agent: could not send: " .. tostring(err))
          end
        end)
      end)
    end)
  end,
}
