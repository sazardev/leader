-- ── Saying what is going to happen, and how sure we are of the result (pure) ─
-- Two sentences the UI repeats everywhere an action is shown:
--   preflight      BEFORE: which model, which tier, what is read, what it should cost
--   verification   AFTER: whether anything checked the answer, and if not, that nothing did
-- "Unverified" is a label, not a warning: advice and prose cannot be checked for free, code can, and the person deciding
-- should know which of the two they are looking at.
local M = {}

---@param n integer
---@return string
local function short(n)
  if n < 1000 then
    return tostring(n)
  end
  return (("%.1fk"):format(n / 1000):gsub("%.0k$", "k"))
end

---@class AgentPreflight
---@field model string                         "claude/haiku"
---@field tier string?                         "main" | "light"
---@field sections { name: string, chars: integer }[]?
---@field chars integer                        what is sent (system + message)
---@field tokens integer?                      the estimate (budget.tokens)
---@field cost number?                         dollars, when the history knows this model's price
---@field profile string?                      capability profile name ("small", "medium", "strong")
---@field samples integer?                     more than one when a checker picks the best of several
---@field steps integer?                       the instruction runs as a chain of this many single steps

--- The facts of a guard request (agent/guards) as a preflight: the estimate comes from the budget guard when it ran
---@param req table
---@return AgentPreflight
function M.from_request(req)
  local est = req.estimate or {}
  return {
    model = (req.backend or "?") .. "/" .. (req.model or "default"),
    tier = req.tier,
    sections = req.sections,
    chars = req.chars,
    tokens = est.tokens,
    cost = est.cost,
    profile = req.profile,
    samples = req.samples,
    steps = req.steps,
  }
end

--- "claude/haiku · light · reads rules, types, around · ~1.8k tok · ~$0.0007"
---@param info AgentPreflight
---@return string
function M.preflight(info)
  local parts = { info.model }
  if info.tier == "light" then
    parts[#parts + 1] = "light"
  end
  if info.profile and info.profile ~= "strong" then
    parts[#parts + 1] = info.profile .. " profile"
  end
  local names = {}
  for _, s in ipairs(info.sections or {}) do
    if s.chars > 0 then
      names[#names + 1] = s.name
    end
  end
  if #names > 0 then
    local shown = #names > 4 and (table.concat(vim.list_slice(names, 1, 4), ", ") .. " +" .. (#names - 4))
      or table.concat(names, ", ")
    parts[#parts + 1] = "reads " .. shown
  end
  local tokens = info.tokens or math.ceil(info.chars / 3.5)
  local cost = ("~%s tok"):format(short(tokens))
  if info.samples and info.samples > 1 then
    cost = ("%d× %s"):format(info.samples, cost)
  end
  if info.steps and info.steps > 1 then
    parts[#parts + 1] = ("%d steps"):format(info.steps)
  end
  parts[#parts + 1] = cost
  if info.cost then
    parts[#parts + 1] = ("~$%.4f"):format(info.cost * (info.samples or 1))
  end
  return table.concat(parts, " · ")
end

---@class AgentTrustFacts
---@field output string               presenter: "replace" | "findings" | "text"
---@field verifies boolean            the verify feature is on and the action takes part in it (action.verify ~= false)
---@field comment_only boolean?       the model's answer cannot touch code (docs: only the comment is merged)
---@field lsp boolean                 a language server is attached to the buffer
---@field build boolean               a build check is configured and will run on save
---@field samples integer?            candidates a checker chose between
---@field checked boolean?            a checker (tests, diagnostics) ran before this was shown

--- { text, level }: level = "checked" (something verified it), "will" (it will be checked after you accept), "none"
---@param f AgentTrustFacts
---@return string text, "checked"|"will"|"none" level
function M.verification(f)
  if f.checked then
    return "verified before showing", "checked"
  end
  if f.output == "findings" then
    return "advice · unverified", "none"
  end
  if f.output ~= "replace" then
    return "answer · unverified", "none"
  end
  if f.comment_only then
    return "comment only · code untouched", "checked"
  end
  if f.verifies and f.lsp and f.build then
    return "checked on accept (LSP) and on save (build)", "will"
  end
  if f.verifies and f.lsp then
    return "checked on accept (LSP)", "will"
  end
  if f.verifies and f.build then
    return "checked on save (build)", "will"
  end
  return "unverified · no language server", "none"
end

--- The line after a proposal was accepted and the language server judged it
---@param heard boolean the server reported (a quiet server proves nothing)
---@return string
function M.after_accept(heard)
  return heard and "verified · no new problems" or "accepted · unverified (the language server stayed silent)"
end

return M
