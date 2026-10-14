-- ── Multi-file plans ─────────────────────────────────────────────────────────
-- `<leader>aM` on a type or function, then what should change. What happens, and what each step costs:
--   1. (free)     where the symbol reaches: language-server references, or `git grep`; collapsed to the declarations that hold
--                 it (plan/locate), capped by `settings.agent.plan`;
--   2. (1 request) the instruction and ONLY the signatures go to the model, which answers an ordered list of steps; the steps
--                 are checked against the real declarations (an invented file or function is dropped);
--   3. (you)      the plan panel: uncheck what you do not want; the estimate follows;
--   4. (1 request per step, in order) each step is a proposal for its declaration; the context carries the plan and what the
--                 steps before it proposed; the proposals wait in the queue (`]`, `[`, accept all) and are verified as you accept.
-- A snapshot (`git stash create`) is taken before step 4 so there is always a way back.
local budget = require "agent.budget"
local log = require "utils.log"
local locate = require "agent.plan.locate"
local prompt = require "agent.plan.prompt"
local protocol = require "agent.protocol"
local selection = require "agent.selection"
local settings = require("core.settings").agent

local M = {}

---@param seed AgentTarget
---@return string
local function root_of(seed)
  local abs = vim.api.nvim_buf_get_name(seed.buf)
  return (abs ~= "" and vim.fs.root(abs, ".git")) or vim.fn.getcwd()
end

--- The estimate line of the plan panel for the chosen steps
---@param instruction string
---@param chosen table[]
---@param sel AgentSelection
---@return AgentBatchItem[] items, string status
local function estimate(instruction, chosen, sel)
  local items, skipped = require("agent.plan.steps").items(instruction, chosen)
  if #items == 0 then
    return items, "nothing selected"
  end
  local verdict = require("agent.batch").estimate(items, sel, "plan")
  local status = ("%d step%s · %s · %s"):format(
    #items,
    #items == 1 and "" or "s",
    selection.label(sel),
    budget.describe(verdict)
  )
  if #skipped > 0 then
    status = status .. (" · skipped: %s"):format(table.concat(skipped, "; "))
  end
  return items, status
end

--- Runs the chosen steps as a batch
---@param instruction string
---@param chosen table[]
---@param root string
---@param sel AgentSelection
local function execute(instruction, chosen, root, sel)
  local items = require("agent.plan.steps").items(instruction, chosen)
  if #items == 0 then
    return log.warn "Agent: none of those steps can be edited any more"
  end
  if settings.plan.snapshot then
    local snap = require("agent.plan.snapshot").take(root)
    if snap then
      log.info("Agent plan: " .. require("agent.plan.snapshot").how_to_return(snap))
    end
  end
  local action = require("agent.plan.action").build()
  require("agent.batch").run {
    title = "plan",
    action = action,
    items = items,
    selection = selection.current(action),
    confirm = false, -- the plan panel showed the estimate and you pressed Enter
  }
end

--- After the plan call: validate, show, run
---@param seed AgentTarget
---@param instruction string
---@param sites AgentPlanSite[]
---@param root string
---@param sel AgentSelection
function M.propose(seed, instruction, sites, root, sel)
  local text = prompt.build(instruction, { name = seed.name, kind = seed.kind, path = seed.path }, sites)
  log.info(
    ("Agent plan: asking %s for the steps (%d declarations, signatures only)…"):format(selection.label(sel), #sites)
  )
  -- the spend guard is in the one-shot call itself (agent/oneshot)
  require("agent").complete({ action = "plan", system = prompt.SYSTEM, prompt = text, tier = "main" }, function(ok, out)
    if not ok then
      return log.warn("Agent plan: " .. tostring(out))
    end
    local steps = prompt.validate(protocol.parse_plan(out), sites)
    if #steps == 0 then
      return log.info "Agent plan: nothing needs to change beyond where you started (use refactor for that)"
    end
    require("agent.plan.ui").open {
      instruction = instruction,
      steps = steps,
      status = function(chosen)
        local _, status = estimate(instruction, chosen, sel)
        return status
      end,
      on_run = function(chosen)
        execute(instruction, chosen, root, sel)
      end,
    }
  end)
end

--- Finds where the change reaches and asks for the plan
---@param seed AgentTarget
---@param instruction string
---@param sel AgentSelection
function M.run(seed, instruction, sel)
  local root = root_of(seed)
  log.info "Agent plan: looking for where it reaches…"
  locate.sites(seed, root, settings.plan, function(sites, how)
    local others = vim.tbl_filter(function(s)
      return not s.seed
    end, sites)
    if #others == 0 then
      return log.info(("Agent plan: nothing else mentions %s (%s): a refactor is enough"):format(seed.name, how))
    end
    M.propose(seed, instruction, sites, root, sel)
  end)
end

--- Entry point of the `plan` action: the symbol under the cursor, then what should change
---@param session { selection: AgentSelection }
function M.start(session)
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "" then
    return log.warn "Agent: only works in file buffers"
  end
  local target_mod = require "agent.context.target"
  local seed = target_mod.resolve(buf, "type")
  if not (seed and seed.name) then
    seed = target_mod.resolve(buf, "function")
  end
  if not (seed and seed.name) then
    return log.warn "Agent plan: put the cursor on the type or function the change is about"
  end
  local sel = session.selection
  require("agent.ui.prompt").ask(
    {
      name = "plan",
      label = "plan",
      input = "what should change across files?",
    },
    seed,
    selection.label(sel),
    function(text)
      if text ~= "" then
        M.run(seed, text, sel)
      end
    end
  )
end

return M
