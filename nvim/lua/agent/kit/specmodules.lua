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
  { id = "money", label = "Money and commerce" },
  { id = "security", label = "Security" },
  { id = "platform", label = "Platform" },
  { id = "quality", label = "Quality" }, -- non-functional: accessibility, speed, reliability
}

---@class SpecModuleReq
---@field title string
---@field statement string
---@field criteria string[]

---@class SpecModule: KitPreset
---@field group string
---@field needs string[]
---@field tech string[]
---@field design string[]
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

--- The `<!-- key: a b c -->` header lines of a file as lists (any key; the preset parser keeps only the ones it knows)
---@param text string
---@return table<string, string[]>
local function header_lists(text)
  local out = {}
  for line in text:gmatch "[^\n]+" do
    if not line:match "^<!%-%-" then
      break
    end
    local key, list = line:match "^<!%-%-%s*([%w_]+):%s*(.-)%s*%-%->"
    if key then
      out[key] = vim.split(list, "[%s,]+", { trimempty = true })
    end
  end
  return out
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
  local head = header_lists(text)
  local needs = head.needs or {}
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
  module.tech = head.tech or {} -- STACK.md add-on axes it pairs with (presets.AXES ids): auth, email, payments…
  module.design = head.design or {} -- DESIGN.md `patterns` add-ons it pairs with: forms, data-tables…
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

--- Names for the `tech` and `design` hints: the add-on axes' labels and the screen patterns' names
---@return { axes: table<string, string>, patterns: table<string, string> }
function M.labels()
  local presets = require "agent.kit.presets"
  local out = { axes = {}, patterns = {} }
  for _, a in ipairs(presets.AXES) do
    out.axes[a.id] = a.label
  end
  for _, p in ipairs(presets.list "design-addons/patterns") do
    out.patterns[p.id] = p.name
  end
  return out
end

---@class SpecKit: KitPreset
---@field modules string[] keys of the modules it picks
---@field tech string[]
---@field design string[]
---@field stacks string[] stack preset ids it is usually built on (a hint)

--- The starter kits: a product type as a set of modules (presets/spec-kits/<id>.md), by name
---@param dir string? tests point it at their own
---@return SpecKit[]
function M.kits(dir)
  local root = (dir or require("agent.kit.presets").dir()) .. "/spec-kits"
  local out = {}
  for file, kind in vim.fs.dir(root) do
    if kind == "file" and file:match "%.md$" then
      local path = root .. "/" .. file
      local text = require("utils.project").read(path) or ""
      local kit = require("agent.kit.presets").parse(file:sub(1, -4), text, path)
      local head = header_lists(text)
      if kit and head.modules then
        kit = kit --[[@as SpecKit]]
        kit.modules, kit.tech, kit.design, kit.stacks = head.modules, head.tech or {}, head.design or {}, head.stacks or {}
        out[#out + 1] = kit
      end
    end
  end
  table.sort(out, function(a, b)
    return a.name:lower() < b.name:lower()
  end)
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

--- The modules SPEC.md talks about without having them: a word of the module's key (payments → payment…) or one of its
--- requirement titles appears in the text. Only what is not there yet; key → the word found (pure, 0 tokens)
---@param spec string
---@param all SpecModule[]
---@param applied table<string, boolean>
---@return table<string, string>
function M.suggest(spec, all, applied)
  local text = " " .. spec:lower():gsub("<!%-%-.-%-%->", " "):gsub("[^%w]+", " ") .. " "
  local out = {}
  for _, m in ipairs(all) do
    local key = M.key(m)
    if not applied[key] then
      local candidates = {}
      local phrase = key:gsub("%-", " ")
      if not phrase:find " " and #phrase >= 6 then
        candidates[#candidates + 1] = { phrase:gsub("s$", ""), true } -- a stem: payment(s), notification(s)
      elseif phrase:find " " then
        candidates[#candidates + 1] = { phrase, false }
      end
      for _, r in ipairs(m.requirements) do
        local title = norm(r.title)
        if #title >= 7 then
          candidates[#candidates + 1] = { title, false }
        end
      end
      for _, c in ipairs(candidates) do
        local word = c[1]
        if text:find(" " .. word .. (c[2] and "" or " "), 1, true) then
          out[key] = word
          break
        end
      end
    end
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

--- A copy of a module with only the requirements you keep; the edge cases and questions of a left-out one go with it
---@param module SpecModule
---@param left_out table<string, boolean>? titles
---@return SpecModule
function M.restrict(module, left_out)
  if not left_out or next(left_out) == nil then
    return module
  end
  local copy = vim.deepcopy(module)
  copy.requirements = vim.tbl_filter(function(r)
    return not left_out[r.title]
  end, module.requirements)
  local function kept(list)
    return vim.tbl_filter(function(x)
      return not (x.req and left_out[x.req])
    end, list)
  end
  copy.edge_cases, copy.questions = kept(module.edge_cases), kept(module.questions)
  return copy
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

--- Everything a choice does to SPEC.md (pure): the modules with what they need, minus what SPEC.md has and what you left
--- out of each, the text that results and what came in
---@param spec string
---@param all SpecModule[]
---@param chosen string[] keys
---@param left_out table<string, table<string, boolean>>? key → titles of requirements not wanted
---@return { list: SpecModule[], pulled: string[], spec: string, result: SpecModuleResult }
function M.plan(spec, all, chosen, left_out)
  left_out = left_out or {}
  local list, pulled = M.resolve(chosen, all, M.applied(spec, all))
  local restricted = vim.tbl_map(function(m)
    return M.restrict(m, left_out[M.key(m)])
  end, list)
  restricted = vim.tbl_filter(function(m)
    return #m.requirements > 0
  end, restricted)
  local new, result = M.apply_all(spec, restricted)
  return { list = restricted, pulled = pulled, spec = new, result = result }
end

--- The lines `new` has that `old` does not, hunk by hunk with an empty line between hunks (what a preview shows)
---@param old string
---@param new string
---@return string[]
function M.added_lines(old, new)
  ---@type integer[][]
  local hunks = (vim.text and vim.text.diff or vim.diff)(old .. "\n", new .. "\n", { result_type = "indices" })
  local lines = vim.split(new, "\n", { plain = true })
  local out = {}
  for _, h in ipairs(hunks) do
    if h[4] > 0 then
      if #out > 0 then
        out[#out + 1] = ""
      end
      for i = h[3], h[3] + h[4] - 1 do
        out[#out + 1] = lines[i]
      end
    end
  end
  return out
end

--- Asks, writes SPEC.md (the old one to the trash), says what came in
---@param root string
---@param spec string
---@param list SpecModule[]
---@param pulled string[]
---@param hooks { on_cancel: fun()?, on_written: fun()? }? the marketplace stays open under the question and closes once written
local function confirm(root, spec, list, pulled, hooks)
  hooks = hooks or {}
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
  modal.confirm(lines, { title = "Add to SPEC.md", confirm = "Add", on_cancel = hooks.on_cancel }, function()
    if hooks.on_written then
      hooks.on_written()
    end
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

--- One module, from the library (`/` → ⏎): the marketplace with it picked, to read it and see what SPEC.md gets
---@param module SpecModule
function M.use(module)
  M.open { pick = { M.key(module) } }
end

--- One starter kit, from the library: the marketplace with its modules picked
---@param kit SpecKit
function M.use_kit(kit)
  M.open { pick = kit.modules }
end

--- <leader>aSm: the marketplace (specmarket.lua): read each module, pick, leave requirements out, see what SPEC.md gets
---@param opts { pick: string[]? }? `pick`: modules already picked (from a kit or a module found in the library)
---@return MarketState?
function M.open(opts)
  local root, spec = spec_here()
  if not root then
    return
  end
  local all = M.all()
  local market = require "agent.kit.specmarket"
  return market.new {
    root = root,
    spec = spec,
    all = all,
    kits = M.kits(),
    labels = M.labels(),
    pick = opts and opts.pick,
    applied = M.applied(spec, all),
    on_add = function(plan, st)
      if #plan.list == 0 then
        return require("utils.log").info "Setup: nothing new to add"
      end
      local win = vim.api.nvim_get_current_win()
      confirm(root, spec, plan.list, plan.pulled, {
        on_cancel = function() -- back to the marketplace as it was
          if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_set_current_win(win)
          end
        end,
        on_written = function()
          market.close(st)
        end,
      })
    end,
  }
end

return M
