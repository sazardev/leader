-- ── Feature slice (<leader>aSbf): one requirement, end to end ────────────────
-- After the first build most work is a new feature. This picks one requirement of SPEC.md (● it already has a test,
-- ○ not yet) or takes a new one in your words, then builds only that slice on the project as it is (build scope
-- `feature`: the domain it needs, the interface that reaches it, the tests of its acceptance criteria, following the
-- patterns the code already uses).
-- A new feature: you describe it on the draft page, one request turns it into a requirement (JSON: title, statement,
-- Given/When/Then criteria, edge cases, questions it cannot answer), the kit writes it into SPEC.md in the document's own
-- style as the next FR-n (its edge cases and questions under their sections), after you confirm; the old SPEC.md goes to
-- the trash. The text work is pure (tested in test-kit-feature.lua).
local M = {}

---@param text string
---@return string[]
local function lines_of(text)
  return vim.split((text or ""):gsub("\r\n", "\n"), "\n", { plain = true })
end

--- The next requirement id: one more than the highest FR-n anywhere in SPEC.md
---@param spec string
---@return string
function M.next_id(spec)
  local top = 0
  for n in (spec or ""):gmatch "FR%-(%d+)" do
    top = math.max(top, tonumber(n))
  end
  return "FR-" .. (top + 1)
end

--- How SPEC.md writes a requirement: `### FR-1: Title` (heading) or `- **FR-1** Title: …` (list), with the indent of its
--- criteria
---@param spec string
---@return { kind: "heading"|"list", level: string?, bold: boolean, indent: string }
function M.style(spec)
  local lines = lines_of(spec)
  for i, l in ipairs(lines) do
    local hashes = l:match "^(#+)%s+%**FR%-%d+"
    if hashes then
      return { kind = "heading", level = hashes, bold = l:find "%*%*FR" ~= nil, indent = "" }
    end
    if l:match "^[-*]%s+%**FR%-%d+" then
      local indent = (lines[i + 1] or ""):match "^(%s+)[-*]%s" or "  "
      return { kind = "list", bold = l:find "%*%*FR" ~= nil, indent = indent }
    end
  end
  return { kind = "heading", level = "###", bold = false, indent = "" }
end

---@class FeatureData
---@field title string
---@field statement string
---@field criteria string[]
---@field edge_cases string[]
---@field questions string[]
---@field builds_on string[]

--- The model's requirement, checked: nil and why when it is not usable
---@param text string
---@return FeatureData?, string?
function M.parse(text)
  local data = require("agent.kit.build.clean").json(text or "")
  if type(data) ~= "table" then
    return nil, "the answer is not one JSON object"
  end
  local function list(v)
    return vim.tbl_filter(function(x)
      return type(x) == "string" and vim.trim(x) ~= ""
    end, type(v) == "table" and v or {})
  end
  local out = {
    title = type(data.title) == "string" and vim.trim(data.title) or "",
    statement = type(data.statement) == "string" and vim.trim(data.statement) or "",
    criteria = list(data.criteria),
    edge_cases = list(data.edge_cases),
    questions = list(data.questions),
    builds_on = list(data.builds_on),
  }
  if out.title == "" or out.statement == "" or #out.criteria == 0 then
    return nil, "the requirement has no title, statement or acceptance criteria"
  end
  return out
end

--- The requirement as SPEC.md writes them (pure)
---@param id string
---@param data FeatureData
---@param style table
---@return string[]
function M.render(id, data, style)
  local name = style.bold and ("**" .. id .. "**") or id
  local out = {}
  local builds_on = #data.builds_on > 0 and (" Builds on " .. table.concat(data.builds_on, ", ") .. ".") or ""
  if style.kind == "list" then
    out[#out + 1] = ("- %s %s: %s%s"):format(name, data.title, data.statement, builds_on)
    for _, c in ipairs(data.criteria) do
      out[#out + 1] = style.indent .. "- " .. c
    end
  else
    vim.list_extend(
      out,
      { ("%s %s: %s"):format(style.level or "###", name, data.title), "", data.statement .. builds_on, "" }
    )
    for _, c in ipairs(data.criteria) do
      out[#out + 1] = "- " .. c
    end
  end
  return out
end

--- `rows` added at the end of a `## title` section (the section added at the end when SPEC.md has none)
---@param lines string[]
---@param title string
---@param rows string[]
---@param gap boolean? a blank line before the rows (a heading-style requirement)
local function append(lines, title, rows, gap)
  local first
  for i, l in ipairs(lines) do
    if l:match("^##%s+" .. vim.pesc(title) .. "%s*$") then
      first = i
      break
    end
  end
  if not first then
    while #lines > 0 and lines[#lines] == "" do
      table.remove(lines)
    end
    vim.list_extend(lines, { "", "## " .. title, "" })
    vim.list_extend(lines, rows)
    lines[#lines + 1] = ""
    return
  end
  local last = #lines
  for j = first + 1, #lines do
    if lines[j]:match "^##%s" then
      last = j - 1
      break
    end
  end
  while last > first and lines[last] == "" do
    last = last - 1
  end
  -- a blank line first after a heading (an empty section) and between heading-style requirements
  local block = (gap or last == first) and vim.list_extend({ "" }, rows) or rows
  for k = #block, 1, -1 do
    table.insert(lines, last + 1, block[k])
  end
end

--- A requirement's edge cases under Edge cases and its questions under Open questions (numbered on from the last `Qn`
--- when the section numbers them), into `lines` (pure)
---@param lines string[]
---@param spec string the text `lines` came from (where the last `Qn` is read)
---@param id string
---@param edge_cases string[]
---@param questions string[]
local function extras(lines, spec, id, edge_cases, questions)
  if #edge_cases > 0 then
    append(
      lines,
      "Edge cases",
      vim.tbl_map(function(e)
        return ("- (%s) %s"):format(id, e)
      end, edge_cases)
    )
  end
  if #questions > 0 then
    local q = 0
    for n in ((spec .. "\n## "):match "\n## Open questions%s*\n(.-)\n## " or ""):gmatch "Q(%d+)" do
      q = math.max(q, tonumber(n))
    end
    append(
      lines,
      "Open questions",
      vim.tbl_map(function(question)
        if q > 0 then
          q = q + 1
          return ("- Q%d (%s): %s"):format(q, id, question)
        end
        return ("- (%s) %s"):format(id, question)
      end, questions)
    )
  end
end

---@param text string
---@return string[]
local function trimmed(text)
  local lines = lines_of(text)
  while #lines > 0 and lines[#lines] == "" do
    table.remove(lines)
  end
  return lines
end

--- SPEC.md with the new requirement (pure): in Requirements, its edge cases in Edge cases, its questions in Open
--- questions (numbered on from the last `Qn` when the section numbers them)
---@param spec string
---@param id string
---@param data FeatureData
---@return string
function M.add(spec, id, data)
  local style = M.style(spec)
  local lines = trimmed(spec)
  append(lines, "Requirements", M.render(id, data, style), style.kind == "heading")
  extras(lines, spec, id, data.edge_cases, data.questions)
  return table.concat(lines, "\n") .. "\n"
end

--- SPEC.md with edge cases and questions for a requirement it already has (pure): the spec modules' extras for one you
--- wrote yourself
---@param spec string
---@param id string
---@param edge_cases string[]
---@param questions string[]
---@return string
function M.add_extras(spec, id, edge_cases, questions)
  local lines = trimmed(spec)
  extras(lines, spec, id, edge_cases, questions)
  return table.concat(lines, "\n") .. "\n"
end

--- The text of one requirement (pure): from its line to the next requirement or heading, then every other line of
--- SPEC.md that names it (its edge cases, its open questions)
---@param spec string
---@param id string
---@return string?
function M.block(spec, id)
  local lines = lines_of(spec)
  local pat = id:gsub("%-", "%%-") .. "%f[%D]"
  local start
  for _, r in ipairs(require("agent.kit.coverage").requirements(spec)) do
    if r.id == id then
      start = r.line
    end
  end
  if not start then
    return nil
  end
  local heading = lines[start]:match "^#+" ~= nil
  local out = { lines[start] }
  local stop = start
  for j = start + 1, #lines do
    local l = lines[j]
    local other = l:match "^[%s#%-*|]*%**FR%-%d+" and not l:find(pat)
    -- the next requirement, a heading, the next bullet of a list, or a spec module's mark (it opens the next block)
    if l:match "^##?#?%s" or other or (not heading and l:match "^[-*]%s") or l:match "^<!%-%-" then
      break
    end
    out[#out + 1] = l
    stop = j
  end
  while #out > 1 and vim.trim(out[#out]) == "" do
    table.remove(out)
  end
  local related = {}
  for i, l in ipairs(lines) do
    if (i < start or i > stop) and l:find(pat) and not l:match "^#" then
      related[#related + 1] = l
    end
  end
  if #related > 0 then
    vim.list_extend(out, { "", "Elsewhere in SPEC.md:" })
    vim.list_extend(out, related)
  end
  return table.concat(out, "\n")
end

--- The build task of a requirement
---@param spec string
---@param req CoverageReq
---@return BuildTask
function M.task(spec, req)
  return { id = req.id, title = req.title, text = M.block(spec, req.id) or (req.id .. " " .. req.title) }
end

--- Opens the feature build of a requirement (its view is the confirmation: nothing is planned before ⏎)
---@param root string
---@param req CoverageReq
function M.build(root, req)
  local spec = require("utils.project").read(root .. "/SPEC.md") or ""
  require("agent.kit.build").open("feature", M.task(spec, req))
end

--- A new requirement in your words: draft → one request → the requirement shown → SPEC.md updated → its build
---@param root string
---@param spec string
local function describe(root, spec)
  local log = require "utils.log"
  local id = M.next_id(spec)
  require("agent.kit.draft").open({
    id = "feature",
    title = ("%s · describe the feature"):format(id),
    hint = {
      "What should it do? Write it any way: who uses it, what they do, what they see, the rules, what can go wrong.",
      ("It comes back as %s in SPEC.md (acceptance criteria, edge cases, open questions), then it is built."):format(
        id
      ),
    },
  }, function(text)
    local req = require("agent.kit.prompts").feature(text, spec, id)
    local sel = require("agent.selection").current { name = req.action, tier = req.tier }
    if not sel then
      return log.warn "Setup: no agent backend found (<leader>am)"
    end
    req.label = "writing " .. id
    log.info(("Setup: writing %s with %s…"):format(id, require("agent.selection").label(sel)))
    require("agent").complete(req, function(ok, answer)
      local data, why = ok and M.parse(answer)
      if not data then
        return log.warn(("Setup: %s was not written: %s"):format(id, ok and why or answer))
      end
      local modal = require "utils.modal"
      local shown = {
        { { id .. " " .. data.title, modal.hl.file } },
        { { data.statement, modal.hl.muted } },
        "",
      }
      for _, c in ipairs(data.criteria) do
        shown[#shown + 1] = { { "  " .. c, modal.hl.muted } }
      end
      if #data.questions > 0 then
        shown[#shown + 1] = ""
        shown[#shown + 1] = {
          {
            ("%d open question%s: the plan decides them, SPEC.md keeps them for you"):format(
              #data.questions,
              #data.questions == 1 and "" or "s"
            ),
            modal.hl.muted,
          },
        }
      end
      modal.confirm(shown, { title = "Add to SPEC.md and build it", confirm = "Add and build" }, function()
        local path, err = require("agent.kit").write(root, "SPEC.md", M.add(spec, id, data), true)
        if not path then
          return log.warn("Setup: " .. err)
        end
        require("agent.kit.draft").forget "feature"
        vim.cmd.checktime()
        log.info(("Setup: %s added to SPEC.md (the previous one is in the trash: <leader>Fu)"):format(id))
        local updated = require("utils.project").read(path) or ""
        local found = vim.tbl_filter(function(r)
          return r.id == id
        end, require("agent.kit.coverage").requirements(updated))[1]
        M.build(root, found or { id = id, title = data.title, line = 0, tests = {} })
      end)
    end)
  end)
end

--- <leader>aSbf: a requirement of SPEC.md to build, or a new one
function M.open()
  local log = require "utils.log"
  local root = require("agent.kit.snapshot").root()
  local read = require("utils.project").read
  local spec = read(root .. "/SPEC.md")
  if not spec or vim.trim(spec) == "" then
    return log.error "Build: a feature is built from SPEC.md: write it first (<leader>aSs)"
  end
  if not read(root .. "/STACK.md") then
    return log.error "Build: a feature follows STACK.md: write it first (<leader>aSt)"
  end
  local coverage = require "agent.kit.coverage"
  local report = coverage.report(coverage.collect(root))
  local items = {
    {
      label = "＋ new",
      desc = ("describe a feature: it becomes %s in SPEC.md, then it is built"):format(M.next_id(spec)),
      path = root .. "/SPEC.md",
      value = { new = true },
    },
  }
  for _, r in ipairs(report.requirements) do
    items[#items + 1] = {
      label = (#r.tests > 0 and "● " or "○ ") .. r.id,
      desc = r.title .. (#r.tests > 0 and "  · tested" or ""),
      path = root .. "/SPEC.md",
      lnum = r.line,
      value = r,
    }
  end
  require("tasks.picker").choose(items, {
    title = "Build a feature · ○ no test yet · ● tested",
    preview = true,
    width = 12,
    select = 1,
  }, function(v)
    if v.new then
      return describe(root, spec)
    end
    M.build(root, v)
  end)
end

return M
