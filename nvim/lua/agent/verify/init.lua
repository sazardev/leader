-- ── Verification after accepting ─────────────────────────────────────────────
-- Accepting a proposal used to be the end. Now the code gets checked, for free:
--   1. before it is written, the buffer's LSP/linter diagnostics are remembered;
--   2. after, we wait for the language server to settle and compare (verify/regressions): what is NEW is what the change broke;
--   3. nothing new → one quiet line; something new → a question: try again with those errors? (verify/retry);
--   4. optionally, when you save, the project is built and the errors on that code are treated the same (verify/build).
-- No tokens are spent unless you say yes to the retry. It subscribes to the replace presenter's events: that presenter
-- does not know this exists.
local anchor = require "agent.anchor"
local events = require "agent.events"
local regressions = require "agent.verify.regressions"
local settle = require "agent.verify.settle"

local M = {}

---@class AgentVerifyState
---@field baseline table[]
---@field ranges { first: integer, last: integer }[]
---@field jobs AgentJob[]
---@field cancel fun()?

---@type table<integer, AgentVerifyState>
local state = {}

local function cfg()
  return require("core.settings").agent.verify
end

---@param job AgentJob
---@return boolean
local function applies(job)
  return cfg().enabled and job.action.output == "replace" and job.action.verify ~= false
end

--- Diagnostics from the language servers and linters (not the agent's own findings: accepting resolves those)
---@param buf integer
---@return table[]
function M.collect(buf)
  local skip = {}
  local ok_f, findings = pcall(require, "agent.output.findings")
  if ok_f then
    skip[findings.namespace()] = true
  end
  local ok_d, ddd = pcall(require, "agent.ddd.diagnose")
  if ok_d then
    skip[ddd.namespace()] = true
  end
  return vim.tbl_filter(function(d)
    return not skip[d.namespace]
  end, vim.diagnostic.get(buf))
end

---@param buf integer
---@param st AgentVerifyState
---@param info { heard: boolean }
local function judge(buf, st, info)
  state[buf] = nil
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local log = require "utils.log"
  local last_job = st.jobs[#st.jobs]
  local new = regressions.new(st.baseline, M.collect(buf), regressions.severity_number(cfg().severity))

  if #new > 0 then
    return require("agent.verify.retry").offer {
      buf = buf,
      diagnostics = new,
      job = last_job,
      source = "lsp",
    }
  end
  if info.heard then
    log.info "Agent: ✓ verified · no new problems"
  end
  -- the build reads the disk: it runs when the buffer is saved
  if cfg().command then
    require("agent.verify.build").arm(buf, st.ranges, cfg(), function(mine, elsewhere, output)
      if #mine > 0 then
        return require("agent.verify.retry").offer {
          buf = buf,
          diagnostics = require("agent.errors.parse").as_diagnostics(mine),
          job = last_job,
          source = "build",
          output = output,
        }
      end
      log.warn(
        ("Agent: the build has %d error%s elsewhere in the project"):format(elsewhere, elsewhere == 1 and "" or "s")
      )
    end)
  end
end

local function on_accepting(ev)
  if not applies(ev.job) then
    return
  end
  -- several proposals accepted together share ONE baseline: the one from before the first
  state[ev.buf] = state[ev.buf] or { baseline = M.collect(ev.buf), ranges = {}, jobs = {} }
end

local function on_accepted(ev)
  local st = state[ev.buf]
  if not st or not applies(ev.job) then
    return
  end
  st.ranges[#st.ranges + 1] = { first = ev.first, last = ev.last }
  st.jobs[#st.jobs + 1] = ev.job
  if st.cancel then
    st.cancel() -- another proposal arrived: judge them all once the server settles again
  end
  st.cancel = settle.wait(ev.buf, { settle_ms = cfg().settle_ms, max_wait_ms = cfg().max_wait_ms }, function(info)
    judge(ev.buf, st, info)
  end)
end

local subscribed = false

function M.setup()
  if subscribed then
    return
  end
  subscribed = true
  events.on("proposal.accepting", on_accepting)
  events.on("proposal.accepted", on_accepted)
end

--- Forgets everything (tests)
function M.reset()
  for _, st in pairs(state) do
    if st.cancel then
      st.cancel()
    end
  end
  state = {}
  subscribed = false
end

return M
