-- ── Review contradictions and redundancies (<leader>aSj), 0 tokens ───────────
-- What STACK.md, DESIGN.md, SPEC.md and AGENTS.md say against each other and against the code, without a model.
-- Every finding has a fix with a preview (Space picks, p shows what it writes, Enter applies what is picked):
--   duplicate-stack-row   the Stack table names the same layer twice with different values (one-of group)
--   duplicate-line        the same non-empty line twice in one section (redundant rule)
--   duplicate-heading     the same `## Title` twice (the second is merged into the first)
--   package-manager       STACK says pnpm but the lockfile says npm/bun/yarn (or the reverse)
--   agents-link           AGENTS.md does not link a document that exists
-- Report-only findings (no automatic fix, Enter opens the file):
--   missing-tool          STACK names a tool the manifest lacks (coverage.missing_tools)
--   folder                a project folder no document mentions (coverage.unmentioned)
-- The pure `find` is tested in scripts/test-kit.lua; `open` shows the report in a split like coverage.
local compose = require "agent.kit.compose"

local M = {}

---@class ReconcileFinding
---@field id string
---@field file string       "STACK.md" etc.
---@field title string
---@field detail string
---@field fix fun(text: string): string?   pure; nil when report-only
---@field kind string       "fix" | "report"

--- Package manager the lockfile says (nil when there is no lockfile or it already matches)
---@param files string[]
---@param stack string
---@return string?
local function pm_mismatch(files, stack)
  local said = compose.package_manager(stack)
  if not said then
    return nil
  end
  local has = {}
  for _, f in ipairs(files) do
    has[f] = true
  end
  if has["pnpm-lock.yaml"] then
    return "pnpm"
  end
  if has["bun.lock"] or has["bun.lockb"] then
    return "bun"
  end
  if has["yarn.lock"] then
    return "yarn"
  end
  if has["package-lock.json"] then
    return "npm"
  end
  return nil
end

---@class ReconcileDocs
---@field agents string?
---@field stack string?
---@field design string?
---@field spec string?

---@class ReconcileFacts
---@field files string[]
---@field paths string[]
---@field manifests table<string, string>
---@field sources table<string, string>

--- Every finding (pure)
---@param docs ReconcileDocs
---@param facts ReconcileFacts
---@return ReconcileFinding[]
function M.find(docs, facts)
  local out = {}
  local function add(f)
    f.kind = f.fix and "fix" or "report"
    f.id = f.file .. "/" .. f.title:gsub("[^%w]+", "-"):lower():gsub("^%-+", ""):gsub("%-+$", "")
    out[#out + 1] = f
  end

  if docs.stack then
    for _, d in ipairs(compose.duplicate_stack_rows(docs.stack)) do
      local rows = d.rows
      add({
        file = "STACK.md",
        title = ("Stack row `%s` twice"):format(d.key),
        detail = table.concat(rows, "  ·  "),
        fix = function(text)
          return compose.dedupe_stack_rows(text)
        end,
      })
    end
    for _, d in ipairs(compose.duplicate_lines(docs.stack)) do
      add({
        file = "STACK.md",
        title = ("`## %s`: a line is twice"):format(d.section),
        detail = d.line:sub(1, 80),
        fix = function(text)
          return compose.dedupe_lines(text)
        end,
      })
    end
    for _, d in ipairs(compose.duplicate_headings(docs.stack)) do
      add({
        file = "STACK.md",
        title = ("`## %s` appears %d times"):format(d.title, d.n),
        detail = "the later headings are removed (their text stays in the first section)",
        fix = function(text)
          local lines = vim.split((text:gsub("\r\n", "\n")), "\n", { plain = true })
          local seen, drop = {}, {}
          for i, line in ipairs(lines) do
            local h = line:match "^##%s+(.-)%s*$"
            if h and h:lower() == d.title:lower() then
              if seen[h:lower()] then
                drop[i] = true
              else
                seen[h:lower()] = true
              end
            end
          end
          local out_lines = {}
          for i, line in ipairs(lines) do
            if not drop[i] then
              out_lines[#out_lines + 1] = line
            end
          end
          return (table.concat(out_lines, "\n"):gsub("%s+$", "")) .. "\n"
        end,
      })
    end
    local want = pm_mismatch(facts.files or {}, docs.stack)
    local said = compose.package_manager(docs.stack)
    if want and said and want ~= said then
      add({
        file = "STACK.md",
        title = ("Stack says `%s` but the lockfile says `%s`"):format(said, want),
        detail = "commands, lockfile and the Stack row are rewritten for " .. want,
        fix = function(text)
          return compose.use_package_manager(text, want)
        end,
      })
    end
    if facts.manifests then
      for _, t in ipairs(require("agent.kit.coverage").missing_tools(docs.stack, facts.manifests)) do
        add({
          file = "STACK.md",
          title = ("STACK names `%s` but %s has not"):format(t.name, t.manifest),
          detail = "add it to the manifest or take it out of STACK.md",
        })
      end
    end
  end

  if docs.agents then
    local present = {}
    for _, f in ipairs(facts.files or {}) do
      if f == "STACK.md" or f == "SPEC.md" or f == "DESIGN.md" then
        present[#present + 1] = f
      end
    end
    local _, missing = compose.link_docs(docs.agents, present)
    if #missing > 0 then
      add({
        file = "AGENTS.md",
        title = "AGENTS.md does not link " .. table.concat(missing, ", "),
        detail = "add the Read first lines",
        fix = function(text)
          return (compose.link_docs(text, present))
        end,
      })
    end
  end

  if docs.design then
    for _, d in ipairs(compose.duplicate_lines(docs.design)) do
      add({
        file = "DESIGN.md",
        title = ("`## %s`: a line is twice"):format(d.section),
        detail = d.line:sub(1, 80),
        fix = function(text)
          return compose.dedupe_lines(text)
        end,
      })
    end
    for _, d in ipairs(compose.duplicate_headings(docs.design)) do
      add({
        file = "DESIGN.md",
        title = ("`## %s` appears %d times"):format(d.title, d.n),
        detail = "the later ones are merged into the first",
        fix = function(text)
          local lines = vim.split((text:gsub("\r\n", "\n")), "\n", { plain = true })
          local seen, drop = {}, {}
          for i, line in ipairs(lines) do
            local h = line:match "^##%s+(.-)%s*$"
            if h and h:lower() == d.title:lower() then
              if seen[h:lower()] then
                drop[i] = true
              else
                seen[h:lower()] = true
              end
            end
          end
          local out_lines = {}
          for i, line in ipairs(lines) do
            if not drop[i] then
              out_lines[#out_lines + 1] = line
            end
          end
          return (table.concat(out_lines, "\n"):gsub("%s+$", "")) .. "\n"
        end,
      })
    end
  end

  if docs.spec then
    for _, d in ipairs(compose.duplicate_lines(docs.spec)) do
      add({
        file = "SPEC.md",
        title = ("`## %s`: a line is twice"):format(d.section),
        detail = d.line:sub(1, 80),
        fix = function(text)
          return compose.dedupe_lines(text)
        end,
      })
    end
  end

  if facts.paths then
    local all = table.concat({ docs.agents or "", docs.stack or "", docs.design or "", docs.spec or "" }, "\n")
    for _, f in ipairs(require("agent.kit.coverage").unmentioned(facts.paths, all)) do
      add({
        file = "STACK.md",
        title = ("Folder `%s` is in no document"):format(f),
        detail = "add it to STACK.md's Project layout or take it into account",
      })
    end
  end

  return out
end

--- The document texts of a project (pure apart from the reads)
---@param root string
---@return ReconcileDocs, ReconcileFacts
function M.collect(root)
  local read = require("utils.project").read
  local cov = require "agent.kit.coverage".collect(root)
  return {
    agents = read(root .. "/AGENTS.md"),
    stack = read(root .. "/STACK.md"),
    design = read(root .. "/DESIGN.md"),
    spec = read(root .. "/SPEC.md"),
  }, {
    files = cov.paths,
    paths = cov.paths,
    manifests = cov.manifests,
    sources = cov.sources,
  }
end

--- <leader>aSj: the findings, with each fix's preview; Enter applies what is picked
function M.open()
  local root = require("agent.kit.snapshot").root()
  local docs, facts = M.collect(root)
  local findings = M.find(docs, facts)
  local log = require "utils.log"
  if #findings == 0 then
    return log.info "Setup: no contradictions or redundancies found"
  end

  local order = { ["STACK.md"] = 1, ["DESIGN.md"] = 2, ["SPEC.md"] = 3, ["AGENTS.md"] = 4 }
  table.sort(findings, function(a, b)
    local ra, rb = order[a.file] or 9, order[b.file] or 9
    if ra ~= rb then
      return ra < rb
    end
    return a.title < b.title
  end)

  -- checklist: fixable items are pickable; report-only are shown unchecked and ignored on apply
  local by_item = {}
  local items = {}
  for i, f in ipairs(findings) do
    by_item[i] = f
    items[#items + 1] = {
      label = f.file .. " · " .. f.title,
      desc = f.fix and f.detail or (f.detail .. " (report only)"),
      checked = f.fix == true or f.fix ~= nil,
    }
  end

  local modal = require "utils.modal"
  local has_fix = vim.iter(findings):any(function(f)
    return f.fix ~= nil
  end)
  if not has_fix then
    local lines = {}
    for _, f in ipairs(findings) do
      lines[#lines + 1] = { { f.file .. " · " .. f.title, modal.hl.file } }
      lines[#lines + 1] = { { "  " .. f.detail, modal.hl.muted } }
    end
    return modal.confirm(lines, { title = "Setup review · " .. vim.fs.basename(root), confirm = "Close" }, function() end)
  end

  -- apply the picked fixes in order to each file's text (cumulative)
  local key_of = { ["STACK.md"] = "stack", ["DESIGN.md"] = "design", ["SPEC.md"] = "spec", ["AGENTS.md"] = "agents" }
  local function applied_for(picked)
    local applied = { stack = docs.stack, design = docs.design, spec = docs.spec, agents = docs.agents }
    for _, i in ipairs(picked) do
      local f = by_item[i]
      if f and f.fix then
        local k = key_of[f.file]
        if applied[k] then
          applied[k] = f.fix(applied[k])
        end
      end
    end
    return applied
  end

  modal.checklist(items, {
    title = "Setup review · " .. vim.fs.basename(root),
    intro = {
      { { "Contradictions and redundancies, with their fixes. Uncheck what you want to keep.", modal.hl.muted } },
      { { "Report-only findings are not pickable.", modal.hl.muted } },
    },
    confirm = "Preview",
    footer = "Space toggle · a all · Esc close",
  }, function(indexes)
    local picked = vim.tbl_filter(function(i)
      return by_item[i] and by_item[i].fix ~= nil
    end, indexes)
    if #picked == 0 then
      return log.info "Setup: nothing applied"
    end
    local applied = applied_for(picked)
    local preview_lines = {
      { { "Apply these changes?", modal.hl.muted } },
      { { "" } },
    }
    for _, key in ipairs { "stack", "design", "spec", "agents" } do
      local before, after = docs[key], applied[key]
      if before ~= after then
        local file = ({ stack = "STACK.md", design = "DESIGN.md", spec = "SPEC.md", agents = "AGENTS.md" })[key]
        preview_lines[#preview_lines + 1] = { { file, modal.hl.key } }
        local added = require("agent.kit.specmodules").added_lines(before or "", after or "")
        if #added == 0 then
          preview_lines[#preview_lines + 1] = { { "  (rows rewritten, no new lines)", modal.hl.muted } }
        end
        for _, l in ipairs(added) do
          preview_lines[#preview_lines + 1] = { { "  " .. l, l:match "^#" and modal.hl.file or modal.hl.muted } }
        end
        preview_lines[#preview_lines + 1] = { { "" } }
      end
    end
    modal.confirm(preview_lines, { title = "Setup review · preview", confirm = "Apply" }, function()
      local touched = {}
      for _, i in ipairs(picked) do
        local f = by_item[i]
        if f and f.fix then
          touched[f.file] = true
        end
      end
      local made = {}
      for file in pairs(touched) do
        local k = key_of[file]
        local path = root .. "/" .. file
        if applied[k] and applied[k] ~= docs[k] then
          local buf = vim.fn.bufnr(path)
          if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified then
            log.warn(("Setup: %s has unsaved changes: save them first"):format(file))
          else
            local f, err = io.open(path, "w")
            if f then
              f:write(applied[k])
              f:close()
              made[#made + 1] = file
            else
              log.warn("Setup: " .. tostring(err))
            end
          end
        end
      end
      if #made > 0 then
        vim.cmd.checktime()
        log.info("Setup: fixed " .. table.concat(made, ", "))
        vim.cmd.edit(vim.fn.fnameescape(root .. "/" .. made[1]))
      end
    end)
  end)
end

return M
