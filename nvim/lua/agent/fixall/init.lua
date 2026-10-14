-- ── Fix all ──────────────────────────────────────────────────────────────────
-- Every finding of the file (agent findings and DDD violations, LSP and linter diagnostics) turned into proposals, one
-- per function that holds any: the grouping (fixall/group) decides what is asked, the batch (agent/batch) asks it once
-- with the total estimate and runs it, the queue lets you review the proposals. Nothing here talks to a model.
local group = require "agent.fixall.group"
local log = require "utils.log"
local settings = require("core.settings").agent.fixall

local M = {}

--- Diagnostics of `buf` from the configured sources, at or above the configured severity
---@param buf integer
---@return AgentDiag[]
function M.collect(buf)
  local ok_f, findings = pcall(require, "agent.output.findings")
  local ok_d, ddd = pcall(require, "agent.ddd.diagnose")
  local agent_ns = {}
  if ok_f then
    agent_ns.findings = findings.namespace()
  end
  if ok_d then
    agent_ns.ddd = ddd.namespace()
  end
  local want = {}
  for _, source in ipairs(settings.sources) do
    want[source] = true
  end
  local out = {}
  for _, d in ipairs(vim.diagnostic.get(buf)) do
    local kind = (d.namespace == agent_ns.findings and "findings") or (d.namespace == agent_ns.ddd and "ddd") or "lsp"
    if want[kind] then
      out[#out + 1] = d
    end
  end
  return group.at_least(out, group.severity_number(settings.min_severity))
end

--- The scope (function, else type) a 1-based line sits in
---@param buf integer
---@return fun(line: integer): table?
function M.resolver(buf)
  local scopes = require "agent.context.scopes"
  return function(line)
    for _, kind in ipairs { "function", "class" } do
      local found = scopes.enclosing(buf, line - 1, kind)
      if found then
        return { first = found.first, last = found.last, name = found.name, kind = kind }
      end
    end
    return nil
  end
end

--- Batch items (one per group) for `diags` in `buf`
---@param buf integer
---@param diags AgentDiag[]
---@return AgentBatchItem[]
function M.items(buf, diags)
  local target_mod = require "agent.context.target"
  local items = {}
  for _, g in ipairs(group.by_scope(diags, M.resolver(buf))) do
    local target = target_mod.of_range(buf, g.kind, g.first, g.last, g.name)
    if target then
      items[#items + 1] = {
        label = g.name or ("lines %d-%d"):format(g.first, g.last),
        target = target,
        count = #g.diags,
        diags = g.diags,
      }
    end
  end
  return items
end

---@param opts { buf: integer?, diagnostics: AgentDiag[]?, title: string?, action: table?, meta: table?, confirm: boolean? }?
function M.run(opts)
  opts = opts or {}
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "" then
    return log.warn "Agent: only works in file buffers"
  end
  local diags = opts.diagnostics or M.collect(buf)
  local items = M.items(buf, diags)
  if #items == 0 then
    return log.info "Agent: nothing to fix here (no findings or diagnostics at that severity)"
  end
  require("agent.batch").run {
    title = opts.title or "fix all",
    action = opts.action or require("agent.actions").get "fix_block",
    items = items,
    confirm = opts.confirm,
    meta = opts.meta,
  }
end

return M
