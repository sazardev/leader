-- ── Architecture decision records (docs/adr/), 0 tokens ──────────────────────
-- Every build's plan names the decisions that shape the code (libraries, patterns, data flow). When its review is
-- accepted they are written as one ADR in the usual shape (`docs/adr/NNNN-title.md`: Status, Context, Decision,
-- Consequences) with an index next to them (`docs/adr/README.md`, linked from AGENTS.md "Read first"), so the next
-- person or agent knows why the code is the way it is. Only decisions no earlier ADR records go in: a build that decides
-- nothing new writes nothing. The next builds follow them: `summary` is the plan request's <decisions> (every decision
-- still in force), and a plan that must reverse one says `Supersedes ADR NNNN: …`, which its ADR records (Status) and the
-- index shows next to the old one (never edited). The text work is pure (tested in test-kit-records.lua); `record` reads
-- and writes.
local M = {}

M.DIR = "docs/adr"
M.INDEX = "docs/adr/README.md"
M.SECTIONS = { "Status", "Context", "Decision", "Consequences" }

--- "Riverpod for state, one Notifier per screen" → "riverpod-for-state-one-notifier-per-screen" (at most 6 words)
---@param text string
---@return string
function M.slug(text)
  local words = {}
  for w in text:lower():gsub("[^%w%s%-]", " "):gmatch "[%w%-]+" do
    if #words < 6 then
      words[#words + 1] = w
    end
  end
  return #words > 0 and table.concat(words, "-") or "decision"
end

--- The number the next ADR takes, from the names of those there (`0003-x.md` → 4)
---@param names string[]
---@return integer
function M.next_number(names)
  local top = 0
  for _, n in ipairs(names) do
    local num = tonumber(n:match "^(%d%d%d%d)%-")
    if num and num > top then
      top = num
    end
  end
  return top + 1
end

--- A decision as it is compared (case, spacing and punctuation do not make it new)
---@param text string
---@return string
local function key(text)
  return vim.trim(text:lower():gsub("[%p%s]+", " "))
end

--- The decisions the ADRs already record: every bullet of their "## Decision" sections
---@param texts string[]
---@return table<string, boolean>
function M.recorded(texts)
  local out = {}
  for _, text in ipairs(texts) do
    local body = ("\n" .. text .. "\n## "):match "\n## Decision%s*\n(.-)\n## " or ""
    for line in body:gmatch "[^\n]+" do
      local item = line:match "^%s*[-*]%s+(.+)$"
      if item then
        out[key(item)] = true
      end
    end
  end
  return out
end

---@class AdrEntry
---@field title string
---@field date string
---@field context string
---@field architecture string?
---@field decisions string[]
---@field created string[]
---@field changed string[]

--- The ADR of a build: its plan's decisions that `recorded` does not have yet; nil when there are none
---@param run BuildRun
---@param recorded table<string, boolean>
---@param date string
---@return AdrEntry?
function M.entry(run, recorded, date)
  local plan = run.plan
  if not plan then
    return nil
  end
  local decisions = vim.tbl_filter(function(d)
    return type(d) == "string" and vim.trim(d) ~= "" and not recorded[key(d)]
  end, plan.decisions or {})
  if #decisions == 0 then
    return nil
  end
  local scope = require "agent.kit.build.scope"
  local what = scope.title(run.scope, run.task)
  local created, changed = {}, {}
  for _, f in ipairs(run.files or {}) do
    if f.state ~= "skipped" then
      table.insert(f.existed and changed or created, f.path)
    end
  end
  local title = run.task and run.task.title or (what ~= "" and what:gsub(" · from .*", "") or plan.name)
  return {
    title = (title:gsub("^%l", string.upper)) .. ": " .. decisions[1]:gsub("%.$", ""),
    date = date,
    context = ("Build of %s (%s). %s"):format(
      plan.name or run.name,
      what ~= "" and what or "the whole project, from AGENTS.md, STACK.md, DESIGN.md and SPEC.md",
      vim.trim(plan.summary or "")
    ),
    architecture = plan.architecture ~= "" and plan.architecture or nil,
    decisions = decisions,
    created = created,
    changed = changed,
  }
end

--- The ADR numbers decisions say they supersede ("Supersedes ADR 0002: …", "supersedes ADR 2 and ADR 0003")
---@param decisions string[]
---@return integer[]
function M.supersedes(decisions)
  local out = {}
  for _, d in ipairs(decisions) do
    if d:lower():find("supersedes", 1, true) then
      for n in d:gmatch "ADR%s*0*(%d+)" do
        if not vim.tbl_contains(out, tonumber(n)) then
          out[#out + 1] = tonumber(n)
        end
      end
    end
  end
  table.sort(out)
  return out
end

--- The decisions of an ADR: the bullets of its Decision section (its Architecture line apart)
---@param text string
---@return string[] decisions, string? architecture
local function decisions_of(text)
  local body = ("\n" .. text .. "\n## "):match "\n## Decision%s*\n(.-)\n## " or ""
  local out = {}
  for line in body:gmatch "[^\n]+" do
    local item = line:match "^%s*[-*]%s+(.+)$"
    if item then
      out[#out + 1] = vim.trim(item)
    end
  end
  return out, body:match "Architecture:%s*([^\n]+)"
end

--- Which ADR supersedes each one (pure): old number → the file of the newer ADR that says so
---@param files table<string, string> name → text
---@return table<integer, string>
function M.superseded(files)
  local names = vim.tbl_keys(files)
  table.sort(names)
  local out = {}
  for _, name in ipairs(names) do
    for _, n in ipairs(M.supersedes((decisions_of(files[name])))) do
      out[n] = name
    end
  end
  return out
end

M.SUMMARY_MAX = 4000

--- The decisions still in force, for the plan request (pure): every ADR not superseded, oldest first, its title and its
--- decisions; the newest kept when they do not fit in SUMMARY_MAX characters. "" when there are none
---@param files table<string, string> name → text
---@return string
function M.summary(files)
  local by = M.superseded(files)
  local names = vim.tbl_keys(files)
  table.sort(names)
  local blocks = {}
  for _, name in ipairs(names) do
    local number = tonumber(name:match "^(%d+)")
    if not by[number] then
      local list, architecture = decisions_of(files[name])
      if #list > 0 or architecture then
        local title = files[name]:match "^# %d+%.%s*([^\n]+)" or name
        local rows = { ("ADR %04d · %s"):format(number, title) }
        if architecture then
          rows[#rows + 1] = "  Architecture: " .. architecture
        end
        for _, d in ipairs(list) do
          rows[#rows + 1] = "  - " .. d
        end
        blocks[#blocks + 1] = table.concat(rows, "\n")
      end
    end
  end
  local kept, size = {}, 0
  for i = #blocks, 1, -1 do -- newest first while they fit, then back in order
    size = size + #blocks[i] + 1
    if size > M.SUMMARY_MAX and #kept > 0 then
      break
    end
    table.insert(kept, 1, blocks[i])
  end
  if #kept == 0 then
    return ""
  end
  return "<decisions>\nAccepted in earlier builds (docs/adr/), still in force:\n"
    .. table.concat(kept, "\n")
    .. "\n</decisions>"
end

--- The ADR's Markdown (pure)
---@param number integer
---@param e AdrEntry
---@return string
function M.render(number, e)
  local out = {
    ("# %04d. %s"):format(number, e.title),
    "",
    "## Status",
    "",
    ("Accepted · %s%s"):format(
      e.date,
      #M.supersedes(e.decisions) > 0
          and (" · supersedes ADR " .. table.concat(
            vim.tbl_map(function(n)
              return ("%04d"):format(n)
            end, M.supersedes(e.decisions)),
            ", "
          ))
        or ""
    ),
    "",
    "## Context",
    "",
    e.context,
    "",
    "## Decision",
    "",
  }
  if e.architecture then
    vim.list_extend(out, { "Architecture: " .. e.architecture, "" })
  end
  for _, d in ipairs(e.decisions) do
    out[#out + 1] = "- " .. d
  end
  vim.list_extend(out, { "", "## Consequences", "" })
  if #e.created > 0 then
    out[#out + 1] = "- Files created: " .. table.concat(e.created, ", ")
  end
  if #e.changed > 0 then
    out[#out + 1] = "- Files changed: " .. table.concat(e.changed, ", ")
  end
  out[#out + 1] =
    "- Later changes follow these decisions; one that reverses a decision gets a new ADR that supersedes this one."
  return table.concat(out, "\n") .. "\n"
end

--- The index (pure): one row per ADR, by number; one a later ADR supersedes says by which
---@param rows { file: string, title: string, date: string, superseded: string? }[]
---@return string
function M.index(rows)
  table.sort(rows, function(a, b)
    return a.file < b.file
  end)
  local out = {
    "# Architecture decisions",
    "",
    "Why the code is the way it is: one record per decision, never edited after it is accepted (a new one supersedes it).",
    "",
    "| ADR | Decision | Date | Status |",
    "|---|---|---|---|",
  }
  for _, r in ipairs(rows) do
    local status = r.superseded and ("superseded by [%s](%s)"):format(r.superseded:match "^(%d+)", r.superseded)
      or "accepted"
    out[#out + 1] = ("| [%s](%s) | %s | %s | %s |"):format(
      r.file:match "^(%d+)" or r.file,
      r.file,
      r.title,
      r.date,
      status
    )
  end
  return table.concat(out, "\n") .. "\n"
end

--- The ADRs of a project: file name → text
---@param root string
---@return table<string, string>
function M.read(root)
  local out = {}
  local dir = root .. "/" .. M.DIR
  for name, kind in vim.fs.dir(dir) do
    if kind == "file" and name:match "^%d%d%d%d%-.*%.md$" then
      out[name] = require("utils.project").read(dir .. "/" .. name) or ""
    end
  end
  return out
end

--- Writes the ADR of a build whose review was just accepted, and the index; the path written, or nil (nothing new)
---@param run BuildRun
---@return string?
function M.record(run)
  local existing = M.read(run.root)
  local entry = M.entry(run, M.recorded(vim.tbl_values(existing)), os.date "%Y-%m-%d")
  if not entry then
    return nil
  end
  local number = M.next_number(vim.tbl_keys(existing))
  local name = ("%04d-%s.md"):format(number, M.slug(entry.title))
  local dir = run.root .. "/" .. M.DIR
  vim.fn.mkdir(dir, "p")
  local f = assert(io.open(dir .. "/" .. name, "w"))
  f:write(M.render(number, entry))
  f:close()
  existing[name] = M.render(number, entry)
  local by = M.superseded(existing)
  local rows = {}
  for file, text in pairs(existing) do
    rows[#rows + 1] = {
      file = file,
      title = text:match "^# %d+%.%s*([^\n]+)" or file,
      date = text:match "\n## Status%s*\n%s*%a+ · ([%d%-]+)" or "",
      superseded = by[tonumber(file:match "^(%d+)")],
    }
  end
  local idx = assert(io.open(run.root .. "/" .. M.INDEX, "w"))
  idx:write(M.index(rows))
  idx:close()
  require("agent.kit").link_file(run.root, M.INDEX, "why the code is the way it is (architecture decisions)")
  return M.DIR .. "/" .. name
end

return M
