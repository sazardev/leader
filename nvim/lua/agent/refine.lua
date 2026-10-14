-- ── Refine: change a proposal, or follow up an answer, without starting over ─────────────────────────────────────────
-- Two moves with the same idea (the previous result is context, you only say what to change):
--   proposal(p)       a proposal is on screen: Tab asks "how should it change?" and replaces it with a new one that
--                     starts from the previous code. The old proposal never touched your buffer.
--   answer(job, body) an explain/ask answer is open: Tab asks the next question with the earlier ones as a conversation.
-- Both launch through `pipeline.launch` with the target they already have: nothing is resolved again, and the model sees the
-- same context plus the previous result (about one ordinary run in tokens).
local anchor = require "agent.anchor"
local log = require "utils.log"
local selection = require "agent.selection"

local M = {}

local THREAD_MAX_CHARS = 4000 -- the oldest turns are dropped past this

--- The action for the next round: same recipe, but it starts from the proposal
---@param base table the action that produced the proposal
---@param job AgentJob
---@return table
local function derive(base, job)
  return vim.tbl_extend("force", base, {
    name = base.name .. "_refine",
    label = base.label .. " · refine",
    input = "how should it change?",
    input_optional = true, -- what you type is appended as the instruction that wins...
    input_needed = true, -- ...but the field cannot be skipped: an empty refinement asks for nothing
    prepare = nil,
    check = nil,
    task = function(env)
      -- the base task may read the ORIGINAL instruction (refactor, ask): keep giving it that one
      return base.task { target = env.target, language = env.language, input = job.input }
        .. "\n\nA previous proposal for <target> is in <previous_proposal>. Start from it, not from <target>, and keep everything the user does not ask to change."
    end,
  })
end

--- A proposal on screen → a new one that builds on it
---@param p AgentProposal
function M.proposal(p)
  local job = p.job
  local first, last = anchor.range(job.buf, job.anchor)
  if not first then
    return log.warn "Agent: that proposal's code is gone"
  end
  if not anchor.unchanged(job) then
    return log.warn "Agent: the code changed since the proposal; there is nothing to refine"
  end
  local action = derive(job.action, job)
  local target = vim.deepcopy(job.target)
  target.first, target.last = first, last

  require("agent.ui.prompt").ask(action, target, selection.label(job.selection), function(text)
    if text == "" then
      return
    end
    require("agent.output.replace").supersede(p)
    require("agent.pipeline").launch {
      action = action,
      target = target,
      subject = job.subject,
      selection = job.selection,
      input = text,
      extra = { { name = "previous_proposal", text = table.concat(p.raw or p.lines, "\n") } },
      meta = (function()
        local meta = vim.tbl_extend("force", job.meta or {}, {
          parent = job.record_id,
          refine = ((job.meta or {}).refine or 0) + 1,
        })
        meta.hint = nil -- "2/4 · <leader>aA] next" belonged to the batch, not to this proposal (nil in tbl_extend would not remove it)
        return meta
      end)(),
    }
  end)
end

--- The refine key as it reads in a hint: `<Tab>` → `Tab`; nil when it is turned off
---@return string?
function M.key_label()
  local key = require("core.settings").agent.keys.refine
  if not key then
    return nil
  end
  local name = key:gsub("[<>]", "")
  return name:sub(1, 1):upper() .. name:sub(2)
end

--- The conversation so far as text for the prompt: newest turns kept, oldest dropped when it grows
---@param thread { q: string, a: string }[]
---@return string
function M.render_thread(thread)
  local turns = {}
  for _, t in ipairs(thread) do
    turns[#turns + 1] = ("Q: %s\nA: %s"):format(t.q, t.a)
  end
  while #turns > 1 and #table.concat(turns, "\n\n") > THREAD_MAX_CHARS do
    table.remove(turns, 1)
  end
  return "Earlier in this conversation (the user is following up: answer the NEW question, do not repeat what is already said):\n"
    .. table.concat(turns, "\n\n")
end

--- An answer on screen → the next question about the same code
---@param job AgentJob
---@param body string the answer as shown
function M.answer(job, body)
  local win = vim.fn.bufwinid(job.buf)
  if win == -1 then
    return log.warn "Agent: the code window is gone"
  end
  local ask = require("agent.actions").get "ask"
  local sel = selection.current(ask)
  if not sel then
    return log.error "Agent: no backend available: run <leader>am → Setup"
  end
  require("agent.ui.float").close()
  vim.api.nvim_set_current_win(win)

  local thread = vim.deepcopy((job.meta or {}).thread or {})
  thread[#thread + 1] = { q = job.input or job.action.label, a = body }
  local last = math.min(job.target.last, vim.api.nvim_buf_line_count(job.buf))
  local target =
    require("agent.context.target").of_range(job.buf, job.target.kind, job.target.first, last, job.target.name)
  if not target then
    return log.warn "Agent: that code is gone"
  end
  require("agent.ui.prompt").ask(ask, target, selection.label(sel), function(text)
    if text == "" then
      return
    end
    require("agent.pipeline").launch {
      action = ask,
      target = target,
      selection = sel,
      input = text,
      extra = { { name = "conversation", text = M.render_thread(thread) } },
      meta = { thread = thread, parent = job.record_id },
    }
  end)
end

return M
