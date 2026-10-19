-- ── Inline agent: public facade ──────────────────────────────────────────────
-- ONE-shot actions over what you are looking at; no chat, no sidebar. Each piece
-- lives in its own folder, behind a small contract:
--
--   backends/   agent CLIs (claude, opencode)             → add a backend = 1 file
--   actions/    recipes: target, context, prompt, output   → add an action = 1 file
--   context/    target (treesitter) + budgeted providers (rules, schema, LSP...)
--   output/     presenters: replace (inline diff), findings (diagnostics), text (window)
--   ui/         spinner, preview, window, picker, text field
--   handoff/    hand off to a Herdr agent
--   setup/      detection and setup of backends and local models (Ollama, LM Studio...)
--
-- This facade is the only thing the menus use; the rest is not imported from outside.
local M = {}

require("agent.ui.highlights").setup()

--- Runs an action over the target under the cursor (or the visual selection)
---@param name string
---@param opts { range: integer[]? }?
function M.run(name, opts)
  require("agent.pipeline").run(name, opts)
end

---@return integer how many jobs were cancelled
local function cancel_running()
  local running = require("agent.jobs").running()
  for _, job in ipairs(running) do
    require("agent.runner").cancel(job)
  end
  return #running + require("agent.calls").cancel() -- one-shot requests (documents, commit draft...) too
end

--- Cancels the running jobs
function M.cancel()
  local n = cancel_running()
  require("utils.log").info(n > 0 and ("Agent: %d cancelled"):format(n) or "Agent: nothing running")
end

--- Cancels what is running and discards the buffer's pending proposals. It does NOT touch findings: they are
--- "pending" diagnostics and survive the session (removed with `clear`).
function M.stop()
  local n = cancel_running()
  require("agent.output.replace").discard_all(vim.api.nvim_get_current_buf())
  if n > 0 then
    require("utils.log").info(("Agent: %d cancelled"):format(n))
  end
end

function M.accept()
  require("agent.output.replace").accept()
end

function M.reject()
  require("agent.output.replace").reject()
end

--- Discards the agent's findings (review and ddd, also from what is persisted):
---   "line" (default): those on the line or the `first`–`last` range (cursor / selection), one by one
---   "file": all of this file's
---   "all": all of them, in all files
---@param scope "line"|"file"|"all"?
---@param first integer? 1-based (default: the cursor line)
---@param last integer?
function M.clear(scope, first, last)
  local log = require "utils.log"
  local findings, ddd = require "agent.output.findings", require "agent.ddd.diagnose"
  local buf = vim.api.nvim_get_current_buf()
  local count = function(ns, b)
    return #vim.diagnostic.get(b, { namespace = ns })
  end
  local n
  if scope == "all" then
    n = math.max(require("agent.persist").count(), count(findings.namespace()), count(ddd.namespace()))
    findings.clear()
    ddd.clear()
  elseif scope == "file" then
    n = count(findings.namespace(), buf) + count(ddd.namespace(), buf)
    findings.clear(buf)
    ddd.resolve(buf, 1, math.huge)
  else
    first = first or vim.api.nvim_win_get_cursor(0)[1]
    last = last or first
    n = findings.resolve(buf, first, last) + ddd.resolve(buf, first, last)
    if n == 0 then
      return log.info(
        first == last and "Agent: no finding on this line (<leader>aC clears the whole file)"
          or "Agent: no findings in the selection"
      )
    end
  end
  log.info(("Agent: %d finding%s cleared"):format(n, n == 1 and "" or "s") .. (scope == "all" and " (all files)" or ""))
end

--- Reopens the last response (or the last proposal, if it was rejected)
function M.last()
  local log = require "utils.log"
  local job = require("agent.jobs").last()
  if not job then
    return log.info "Agent: nothing to reopen"
  end
  if job.action.output == "text" then
    if not require("agent.ui.float").reopen() then
      log.info "Agent: nothing to reopen"
    end
  elseif job.action.output == "replace" then
    if not vim.api.nvim_buf_is_valid(job.buf) then
      return log.info "Agent: the buffer no longer exists"
    end
    job.anchor = require("agent.anchor").create(job.buf, job.target.first, job.target.last)
    job.t0 = vim.uv.hrtime() -- the time shown is that of the original call, not the current one
    require("agent.output.replace").done(job, job.result)
  else
    log.info "Agent: the findings are already in the buffer (<leader>xd)"
  end
end

--- Asks the AI for a text with no buffer or target (commit messages...): one shot, light
--- model by default. `cb(ok, text | error)`. Returns the process, so it can be cancelled.
---@param req { action: string, system: string, prompt: string, tier: "main"|"light"? }
---@param cb fun(ok: boolean, text: string, usage: table?)
---@return vim.SystemObj?
function M.complete(req, cb)
  return require("agent.oneshot").run(req, cb)
end

--- What the answer cache holds and has saved you, with a button to forget it all (a stored answer is only reused for an
--- identical request, so clearing is rarely needed)
function M.cache()
  local cache = require "agent.cache"
  local text = require "agent.text"
  local s = cache.stats()
  local saved = ("answered %d time%s · saved %s tokens"):format(s.hits, s.hits == 1 and "" or "s", text.tokens(s.tokens))
  if s.cost > 0 then
    saved = saved .. (" · ~$%.4f"):format(s.cost)
  end
  local lines = {
    ("%d answer%s kept (%.1f KB)"):format(s.answers, s.answers == 1 and "" or "s", s.bytes / 1024),
    saved,
  }
  if s.answers == 0 then
    return require("utils.modal").confirm(lines, { title = "Agent cache", confirm = "Nothing to clear" }, function() end)
  end
  require("utils.modal").confirm(lines, { title = "Agent cache", confirm = "Clear", danger = true }, function()
    local n = cache.clear()
    require("utils.log").info(("Agent: %d cached answer%s forgotten"):format(n, n == 1 and "" or "s"))
  end)
end

--- Run history: prompt, response, tokens and cost of each action
function M.history()
  require("agent.ui.history").open()
end

--- Aggregated spend report
function M.report()
  require("agent.ui.history").report()
end

--- Main model, light model and effort, in a single picker
function M.settings()
  require("agent.chooser").menu()
end

return M
