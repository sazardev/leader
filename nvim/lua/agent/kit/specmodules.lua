-- ── SPEC.md modules (<leader>aSm): the requirements every app repeats ──────────
-- Your SPEC.md stays yours: you write the core of your business; the modules add the well-known parts you would
-- otherwise forget (accounts, roles, lists, workspaces, notifications, audit log, uploads, import/export, offline,
-- payments, subscriptions), with their edge cases, and with QUESTIONS where the answer is yours (never invented rules).
-- A module is a plain file presets/spec/<group>/<name>.md in SPEC.md's own shape, without ids:
--   <!-- name: Accounts and sign-in -->  <!-- desc: … -->  <!-- needs: accounts -->   (modules it builds on)
--   ## Requirements    ### Title  +  "The system must…"  +  "- Given …, when …, then …" criteria
--   ## Edge cases      - [Title] what can go wrong: what must happen
--   ## Open questions  - [Title] a question only you can answer
-- Applying one (pure `apply`): every requirement gets the next FR-n in SPEC.md's style (feature.lua), its edge cases and
-- questions go under their sections tagged with its id; a requirement whose title SPEC.md already has is skipped (its
-- extras go to YOUR requirement); `<!-- module: id -->` marks where a module went in, so applying it again adds nothing.
-- Nothing is ever removed. Tested in test-kit-specmodules.lua.
local feature = require "agent.kit.feature"

local M = {}

M.GROUPS = {
  { id = "basics", label = "Every app" },
  { id = "collaboration", label = "Teams" },
  { id = "data", label = "Data" },
  { id = "money", label = "Money" },
}

---@class SpecModuleReq
---@field title string
---@field statement string
---@field criteria string[]

---@class SpecModule: KitPreset
---@field group string
---@field needs string[]
---@field requirements SpecModuleReq[]
---@field edge_cases { req: string?, text: string }[]
---@field questions { req: string?, text: string }[]

--- "[Sign in] text" → "Sign in", "text"; untagged → nil, text
---@param line string
---@return string?, string
local function tagged(line)
  local req, text = line:match "^%[([^%]]+)%]%s*(.+)$"
  if req then
    return vim.trim(req), vim.trim(text)
  end
  return nil, vim.trim(line)
end

--- A module from its file; nil when it has no desc or no requirement
---@param id string "basics/accounts"
---@param text string
---@param path string?
---@return SpecModule?
function M.parse(id, text, path)
  local preset = require("agent.kit.presets").parse(id, text, path)
  if not preset then
    return nil
  end
  local needs = {}
  for line in text:gmatch "[^\n]+" do
    if not line:match "^<!%-%-" then
      break
    end
    local list = line:match "^<!%-%-%s*needs:%s*(.-)%s*%-%->"
    if list then
      needs = vim.split(list, "[%s,]+", { trimempty = true })
    end
  end
  local body = "\n" .. preset.body .. "\n## "
  local reqs = {}
  local current
  for line in ((body:match "\n## Requirements%s*\n(.-)\n## ") or ""):gmatch "[^\n]*" do
    local title = line:match "^###%s+(.+)$"
    local item = line:match "^%s*[-*]%s+(.+)$"
    if title then
      current = { title = vim.trim(title), statement = "", criteria = {} }
      reqs[#reqs + 1] = current
    elseif current and item then
      current.criteria[#current.criteria + 1] = vim.trim(item)
    elseif current and vim.trim(line) ~= "" then
      current.statement = vim.trim(current.statement .. " " .. vim.trim(line))
    end
  end
  if #reqs == 0 then
    return nil
  end
  local function items(section)
    local out = {}
    for line in ((body:match("\n## " .. section .. "%s*\n(.-)\n## ")) or ""):gmatch "[^\n]+" do
      local item = line:match "^%s*[-*]%s+(.+)$"
      if item then
        local req, t = tagged(item)
        out[#out + 1] = { req = req, text = t }
      end
    end
    return out
  end
  local module = preset --[[@as SpecModule]]
  module.group = id:match "^([^/]+)/" or "basics"
  module.needs = needs
  module.requirements = reqs
  module.edge_cases = items "Edge cases"
  module.questions = items "Open questions"
  return module
end

--- Every module, in the order of M.GROUPS (then any other folder), by name inside a group
---@param dir string? tests point it at their own
---@return SpecModule[]
function M.all(dir)
  local root = (dir or require("agent.kit.presets").dir()) .. "/spec"
  local groups, known = {}, {}
  for _, g in ipairs(M.GROUPS) do
    groups[#groups + 1], known[g.id] = g.id, true
  end
  local extra = {}
  for name, kind in vim.fs.dir(root) do
    if kind == "directory" and not known[name] then
      extra[#extra + 1] = name
    end
  end
  table.sort(extra)
  vim.list_extend(groups, extra)
  local out = {}
  for _, g in ipairs(groups) do
    local list = {}
    for file, kind in vim.fs.dir(root .. "/" .. g) do
      if kind == "file" and file:match "%.md$" then
        local path = root .. "/" .. g .. "/" .. file
        local m = M.parse(g .. "/" .. file:sub(1, -4), require("utils.project").read(path) or "", path)
        if m then
          list[#list + 1] = m
        end
      end
    end
    table.sort(list, function(a, b)
      return a.name:lower() < b.name:lower()
    end)
    vim.list_extend(out, list)
  end
  return out
end

--- The short name a module is marked and needed by: "basics/accounts" → "accounts"
---@param module SpecModule
---@return string
function M.key(module)
  return (module.id:gsub("^.*/", ""))
end

--- A title as it is compared: case, punctuation and spacing do not count
---@param title string
---@return string
local function norm(title)
  return vim.trim(title:lower():gsub("[%p%s]+", " "))
end

--- The requirements SPEC.md has, by compared title → its id (`### FR-3: Sign in`, `- **FR-3** Sign in: …`)
---@param spec string
---@return table<string, string>
function M.titles(spec)
  local out = {}
  for _, r in ipairs(require("agent.kit.coverage").requirements(spec)) do
    local title = r.title:match "^(.-):%s" or r.title
    out[norm(title)] = r.id
  end
  return out
end

--- The modules SPEC.md already has: marked by `<!-- module: key -->`, or every requirement of it already there
---@param spec string
---@param modules SpecModule[]
---@return table<string, boolean> key → true
function M.applied(spec, modules)
  local out = {}
  for key in spec:gmatch "<!%-%-%s*module:%s*([%w_%-]+)%s*%-%->" do
    out[key] = true
  end
  local titles = M.titles(spec)
  for _, m in ipairs(modules) do
    local all = true
    for _, r in ipairs(m.requirements) do
      all = all and titles[norm(r.title)] ~= nil
    end
    if all then
      out[M.key(m)] = true
    end
  end
  return out
end

--- The chosen modules with what they need, needs first, without those SPEC.md already has (pure)
---@param chosen string[] keys
---@param modules SpecModule[]
---@param applied table<string, boolean>
---@return SpecModule[] list, string[] added keys a choice needed
function M.resolve(chosen, modules, applied)
  local by = {}
  for _, m in ipairs(modules) do
    by[M.key(m)] = m
  end
  local out, seen, pulled = {}, {}, {}
  local wanted = {}
  for _, k in ipairs(chosen) do
    wanted[k] = true
  end
  local function visit(key)
    if seen[key] or applied[key] or not by[key] then
      return
    end
    seen[key] = true
    for _, n in ipairs(by[key].needs) do
      if not wanted[n] and not applied[n] and by[n] and not seen[n] then
        pulled[#pulled + 1] = n
      end
      visit(n)
    end
    out[#out + 1] = by[key]
  end
  for _, k in ipairs(chosen) do
    visit(k)
  end
  return out, pulled
end

---@class SpecModuleResult
---@field ids string[]       the FR-n added
---@field skipped string[]   titles SPEC.md already had
---@field edge integer
---@field questions integer

--- SPEC.md with one module (pure)
---@param spec string
---@param module SpecModule
---@return string, SpecModuleResult
function M.apply(spec, module)
  local result = { ids = {}, skipped = {}, edge = 0, questions = 0 }
  if spec:find("<!-- module: " .. M.key(module) .. " -->", 1, true) then
    return spec, result
  end
  local function of(list, title, first)
    local out = {}
    for _, x in ipairs(list) do
      if (x.req and norm(x.req) == norm(title)) or (not x.req and first) then
        out[#out + 1] = x.text
      end
    end
    return out
  end
  local marked = false
  for i, r in ipairs(module.requirements) do
    local edges, questions = of(module.edge_cases, r.title, i == 1), of(module.questions, r.title, i == 1)
    local have = M.titles(spec)[norm(r.title)]
    if have then
      result.skipped[#result.skipped + 1] = r.title
      spec = feature.add_extras(spec, have, edges, questions)
    else
      local id = feature.next_id(spec)
      spec = feature.add(spec, id, {
        title = r.title,
        statement = r.statement,
        criteria = r.criteria,
        edge_cases = edges,
        questions = questions,
        builds_on = {},
      })
      result.ids[#result.ids + 1] = id
      if not marked then -- where the module went in: applying it again adds nothing
        marked = true
        local lines = vim.split(spec, "\n", { plain = true })
        for _, req in ipairs(require("agent.kit.coverage").requirements(spec)) do
          if req.id == id then
            table.insert(lines, req.line, "<!-- module: " .. M.key(module) .. " -->")
            break
          end
        end
        spec = table.concat(lines, "\n")
      end
    end
    result.edge, result.questions = result.edge + #edges, result.questions + #questions
  end
  return spec, result
end

--- SPEC.md with several modules, in order (pure)
---@param spec string
---@param list SpecModule[]
---@return string, SpecModuleResult
function M.apply_all(spec, list)
  local total = { ids = {}, skipped = {}, edge = 0, questions = 0 }
  for _, m in ipairs(list) do
    local r
    spec, r = M.apply(spec, m)
    vim.list_extend(total.ids, r.ids)
    vim.list_extend(total.skipped, r.skipped)
    total.edge, total.questions = total.edge + r.edge, total.questions + r.questions
  end
  return spec, total
end

--- Asks, writes SPEC.md (the old one to the trash), says what came in
---@param root string
---@param spec string
---@param list SpecModule[]
---@param pulled string[]
local function confirm(root, spec, list, pulled)
  local log = require "utils.log"
  local new, r = M.apply_all(spec, list)
  if #r.ids == 0 and r.edge == 0 and r.questions == 0 then
    return log.info "Setup: SPEC.md already has all of that"
  end
  local modal = require "utils.modal"
  local names = vim.tbl_map(function(m)
    return m.name
  end, list)
  local lines = {
    { { table.concat(names, " · "), modal.hl.file } },
    "",
    {
      {
        ("%d requirement%s (%s), %d edge case%s, %d open question%s"):format(
          #r.ids,
          #r.ids == 1 and "" or "s",
          #r.ids > 0 and (r.ids[1] .. (#r.ids > 1 and ("–" .. r.ids[#r.ids]) or "")) or "none",
          r.edge,
          r.edge == 1 and "" or "s",
          r.questions,
          r.questions == 1 and "" or "s"
        ),
        modal.hl.muted,
      },
    },
  }
  if #pulled > 0 then
    lines[#lines + 1] = { { "with what they need: " .. table.concat(pulled, ", "), modal.hl.muted } }
  end
  if #r.skipped > 0 then
    lines[#lines + 1] =
      { { "already in SPEC.md, kept as you wrote it: " .. table.concat(r.skipped, ", "), modal.hl.muted } }
  end
  modal.confirm(lines, { title = "Add to SPEC.md", confirm = "Add" }, function()
    local path, why = require("agent.kit").write(root, "SPEC.md", new, true)
    if not path then
      return log.warn("Setup: " .. why)
    end
    vim.cmd.checktime()
    vim.cmd.edit(vim.fn.fnameescape(path))
    log.info(
      ("Setup: SPEC.md · %d requirements added, %d questions to answer · <leader>aSbf builds them one by one (the old SPEC.md is in the trash)"):format(
        #r.ids,
        r.questions
      )
    )
  end)
end

---@return string?, string?
local function spec_here()
  local root = require("agent.kit.snapshot").root()
  local spec = require("utils.project").read(root .. "/SPEC.md")
  if not spec or vim.trim(spec) == "" then
    require("utils.log").error "Setup: modules go into SPEC.md: write yours first (<leader>aSs), then add them"
    return nil
  end
  return root, spec
end

--- One module, from the library (`/` → ⏎)
---@param module SpecModule
function M.use(module)
  local root, spec = spec_here()
  if not root then
    return
  end
  local all = M.all()
  local list, pulled = M.resolve({ M.key(module) }, all, M.applied(spec, all))
  if #list == 0 then
    return require("utils.log").info(("Setup: SPEC.md already has %s"):format(module.name))
  end
  confirm(root, spec, list, pulled)
end

--- <leader>aSm: the modules by group (those SPEC.md has say so), checked ones go in after a confirmation
function M.open()
  local root, spec = spec_here()
  if not root then
    return
  end
  local all = M.all()
  local applied = M.applied(spec, all)
  local labels = {}
  for _, g in ipairs(M.GROUPS) do
    labels[g.id] = g.label
  end
  local items = vim.tbl_map(function(m)
    local there = applied[M.key(m)]
    local needs = #m.needs > 0 and (" · needs " .. table.concat(m.needs, ", ")) or ""
    return {
      label = m.name,
      desc = there and "in SPEC.md"
        or (("%d requirements · %d questions%s"):format(#m.requirements, #m.questions, needs)),
      group = labels[m.group] or m.group,
    }
  end, all)
  require("utils.modal").checklist(items, {
    title = "SPEC.md modules",
    intro = { "What every app repeats, with its edge cases. Where the answer is yours, it comes as a question." },
    confirm = "Add",
    clean = true,
  }, function(chosen)
    local keys = {}
    for _, i in ipairs(chosen) do
      keys[#keys + 1] = M.key(all[i])
    end
    local list, pulled = M.resolve(keys, all, applied)
    if #list == 0 then
      return require("utils.log").info "Setup: nothing new to add"
    end
    confirm(root, spec, list, pulled)
  end)
end

return M
