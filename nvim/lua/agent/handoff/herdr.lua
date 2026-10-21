-- ── Hand off to an agent already running in a Herdr pane ─────────────────────
-- For when the task is bigger than a one-shot action: `file:range` + your instruction
-- is sent to the agent you pick (Claude Code, etc.) and the work continues there.
-- Uses the Herdr CLI (lua/herdr/); only inside Herdr.
local herdr = require "herdr"

local M = {}

---@return boolean
function M.available()
  return herdr.inside()
end

--- Available agents, the ones in this folder first (and without nvim's pane)
---@param cb fun(agents: table[])
function M.agents(cb)
  herdr.agents(function(all, err)
    if err then
      return cb({})
    end
    local cwd, own = vim.fn.getcwd(), vim.env.HERDR_PANE_ID
    local list = vim.tbl_filter(function(a)
      return a.pane_id ~= own
    end, all)
    local function here(a)
      return (a.foreground_cwd or a.cwd or ""):sub(1, #cwd) == cwd and 0 or 1
    end
    table.sort(list, function(a, b)
      if here(a) ~= here(b) then
        return here(a) < here(b)
      end
      return (a.name or "") < (b.name or "")
    end)
    cb(list)
  end)
end

---@param agent table
---@return string
function M.label(agent)
  return ("%s · %s · %s · %s"):format(
    agent.name or agent.pane_id,
    agent.agent or "?",
    agent.agent_status or "?",
    vim.fn.fnamemodify(agent.foreground_cwd or agent.cwd or "", ":~")
  )
end

---@param pane_id string
---@param message string
---@param cb fun(ok: boolean, err: string?)
function M.send(pane_id, message, cb)
  herdr.prompt(pane_id, message, cb)
end

return M
