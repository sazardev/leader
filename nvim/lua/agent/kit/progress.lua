-- ── PROGRESS.md: where the work stands, for whoever picks it up (0 tokens) ────
-- Rewritten by the build every time a run settles (done, failed, stopped), in fixed sections any agent (Claude Code,
-- Codex, opencode, this one) reads before it goes on:
--   Now    the last build: what it built, how it ended, how to resume it
--   Done   a log, one line per build that finished (kept across rewrites, newest first)
--   Open   what is known to be unfinished: failed files and checks, issues the user phase found, SPEC.md's questions
--   Next   the requirements no test proves yet (coverage.lua), the obvious next builds
-- Linked from AGENTS.md "Read first" when it is created. The text work is pure (tested in test-kit-records.lua).
local M = {}

M.FILE = "PROGRESS.md"
M.SECTIONS = { "Now", "Done", "Open", "Next" }
M.MAX_DONE = 30

--- The lines of a section (without its heading and the blank lines around)
---@param text string
---@param title string
---@return string[]
local function section(text, title)
  local body = ("\n" .. (text or "") .. "\n## "):match("\n## " .. title .. "%s*\n(.-)\n## ") or ""
  local out = {}
  for line in body:gmatch "[^\n]+" do
    out[#out + 1] = line
  end
  return out
end

--- What the build is called in the log: "feature FR-8 · Export notes", "domain", "the whole project"
---@param run BuildRun
---@return string
local function what(run)
  local title = require("agent.kit.build.scope").title(run.scope, run.task)
  return title ~= "" and title:gsub(" · from .*$", "") or "the whole project"
end

---@class ProgressFacts
---@field date string
---@field questions integer   open questions in SPEC.md
---@field next CoverageReq[]  requirements no test proves yet
---@field keys string         the key that resumes this build
---@field proof BuildProof?   what the build can honestly claim (build/proof.lua)

--- PROGRESS.md for this run (pure): the previous one's Done log kept, this run on top when it finished
---@param previous string?
---@param run BuildRun
---@param facts ProgressFacts
---@return string
function M.render(previous, run, facts)
  local name = run.plan and run.plan.name or run.name
  local label = what(run)
  local done_count, total = 0, 0
  for _, f in ipairs(run.files or {}) do
    if f.state ~= "skipped" then
      total = total + 1
      if f.state == "done" or f.state == "fixed" then
        done_count = done_count + 1
      end
    end
  end
  local outcome = run.outcome or run.phase
  local out = {
    "# Progress: " .. name,
    "",
    "Where the work stands, for whoever goes on with it. Rewritten after every build; `Done` is a log and is kept.",
    "",
    "## Now",
    "",
    ("- Last build: %s · %s · %s"):format(label, outcome, facts.date),
    ("- Files: %d of %d written · $%.3f"):format(done_count, total, run.totals and run.totals.cost or 0),
  }
  if facts.proof then
    local line = require("agent.kit.build.proof").line(facts.proof):gsub("^ · ", "")
    out[#out + 1] = "- Proof: " .. (line ~= "" and line or "nothing to measure (SPEC.md names no requirements)")
  end
  if run.plan and run.plan.summary and run.plan.summary ~= "" then
    out[#out + 1] = "- What it builds: " .. vim.trim(run.plan.summary)
  end
  if run.phase ~= "done" then
    out[#out + 1] = ("- To resume: %s in Neovim (the run is saved), or go on by hand from `Open`"):format(facts.keys)
  end
  vim.list_extend(out, { "", "## Done", "" })
  local log = section(previous, "Done")
  if run.phase == "done" then
    local entry = ("- %s · %s · %s · $%.3f"):format(facts.date, label, outcome, run.totals and run.totals.cost or 0)
    local prefix = ("- %s · %s · "):format(facts.date, label)
    log = vim.tbl_filter(function(l) -- the same build again today replaces its line
      return l:sub(1, #prefix) ~= prefix
    end, log)
    table.insert(log, 1, entry)
  end
  log = vim.tbl_filter(function(l)
    return l:match "^%- " ~= nil
  end, log)
  if #log == 0 then
    log = { "- nothing finished yet" }
  end
  vim.list_extend(out, vim.list_slice(log, 1, M.MAX_DONE))
  vim.list_extend(out, { "", "## Open", "" })
  local open = {}
  for _, f in ipairs(run.files or {}) do
    if f.state == "failed" or f.state == "pending" or f.state == "writing" then
      open[#open + 1] = ("- `%s`: not written yet (%s)"):format(f.path, f.purpose ~= "" and f.purpose or "planned")
    elseif f.state == "skipped" then
      open[#open + 1] = ("- `%s`: left out in the review"):format(f.path)
    end
  end
  for _, c in ipairs(run.checks or {}) do
    if c.state == "failed" then
      open[#open + 1] = ("- the check `%s` fails"):format(c.label)
    end
  end
  if run.use and (run.use.issues or 0) > 0 then
    open[#open + 1] = ("- using the app found %d issue%s (the build's feed lists them)"):format(
      run.use.issues,
      run.use.issues == 1 and "" or "s"
    )
  end
  if run.outcome and (run.outcome:find "^✗" or run.outcome:find "^⚠") then
    open[#open + 1] = "- " .. run.outcome
  end
  if facts.proof then
    vim.list_extend(open, require("agent.kit.build.proof").open_lines(facts.proof))
  end
  if facts.questions > 0 then
    open[#open + 1] = ("- SPEC.md has %d open question%s: the build decided them in its plan, the answer is yours"):format(
      facts.questions,
      facts.questions == 1 and "" or "s"
    )
  end
  if #open == 0 then
    open = { "- nothing known" }
  end
  vim.list_extend(out, open)
  vim.list_extend(out, { "", "## Next", "" })
  if #facts.next == 0 then
    out[#out + 1] = "- every requirement in SPEC.md has a test that proves it"
  end
  for i, r in ipairs(facts.next) do
    if i > 10 then
      out[#out + 1] = ("- … and %d more (<leader>aSv lists them)"):format(#facts.next - 10)
      break
    end
    out[#out + 1] = ("- %s %s: no test proves it yet (<leader>aSbf builds it)"):format(r.id, r.title)
  end
  return table.concat(out, "\n") .. "\n"
end

--- SPEC.md's open questions (the items of its section)
---@param spec string?
---@return integer
function M.questions(spec)
  local n = 0
  for _, l in ipairs(section(spec or "", "Open questions")) do
    if l:match "^%s*[-*]%s" or l:match "^%s*%d+[.)]%s" then
      n = n + 1
    end
  end
  return n
end

--- Rewrites PROGRESS.md for this run (and links it from AGENTS.md the first time)
---@param run BuildRun
function M.record(run)
  local root = run.root
  local path = root .. "/" .. M.FILE
  local read = require("utils.project").read
  local previous = read(path)
  local coverage = require "agent.kit.coverage"
  local facts = {
    date = os.date "%Y-%m-%d",
    questions = M.questions(read(root .. "/SPEC.md")),
    next = coverage.uncovered(coverage.report(coverage.collect(root))),
    keys = require("agent.kit.build.scope").keys(run.scope),
    proof = run.proof,
  }
  local f = assert(io.open(path, "w"))
  f:write(M.render(previous, run, facts))
  f:close()
  if not previous then
    require("agent.kit").link_file(root, M.FILE, "where the work stands: the last build, what is open, what is next")
  end
end

return M
