-- ── Project kit (<leader>aS): the documents agents read before they code ─────
-- AGENTS.md (how to work here), STACK.md (stack, layout, engineering principles), DESIGN.md (the design system) and
-- SPEC.md (what is being built), at the repository's root. Each one either from presets (0 tokens) or written by the model
-- from what you describe, always in the same sections (compose.DOCS), so an agent finds the same thing in every project.
--   presets.lua   the preset files (presets/design, presets/stack/<category>, presets/principles)   compose.lua  text (pure)
--   snapshot.lua  what the project is made of                    template.lua  AGENTS.md without a model (pure)
--   prompts.lua   the requests to the model                       draft.lua     the page you write a description on
-- Never overwrites in silence: replacing asks first and the old file goes to the trash (`<leader>Fu` brings it back).
-- AGENTS.md links every other document that exists (added to its "Read first" when one is created).
local compose = require "agent.kit.compose"
local log = require "utils.log"
local presets = require "agent.kit.presets"
local snapshot = require "agent.kit.snapshot"

local M = {}

---@type table<string, boolean> documents with a request on its way
local busy = {}

---@param path string
---@return boolean
local function exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

---@param root string
---@param file string
---@return string
local function shown(root, file)
  return vim.fn.fnamemodify(root, ":~") .. "/" .. file
end

--- A buffer with unsaved changes to that file (writing under it would fight with them)
---@param path string
---@return boolean
local function unsaved(path)
  local buf = vim.fn.bufnr(path)
  return buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified
end

--- Writes a document at the root. `replace`: the file there goes to the trash first. Returns the path, or nil and why.
---@param root string
---@param file string
---@param text string
---@param replace boolean?
---@return string? path, string? reason
function M.write(root, file, text, replace)
  local path = root .. "/" .. file
  if exists(path) then
    if not replace then
      return nil, file .. " is already there"
    end
    if unsaved(path) then
      return nil, file .. " has unsaved changes in a buffer: save or discard them first"
    end
    local entry, why = require("files.ops").trash(path)
    if not entry then
      return nil, why
    end
  end
  local f, err = io.open(path, "w")
  if not f then
    return nil, err
  end
  f:write(text)
  f:close()
  return path
end

--- AGENTS.md gets a "Read first" line for the documents that are there and not linked yet
---@param root string
---@return string[] added
function M.link(root)
  local path = root .. "/AGENTS.md"
  local text = require("utils.project").read(path)
  if not text or unsaved(path) then
    return {}
  end
  local present = vim.tbl_filter(
    function(file)
      return exists(root .. "/" .. file)
    end,
    vim.tbl_map(function(d)
      return d.file
    end, compose.DOCS)
  )
  local new, added = compose.link_docs(text, present)
  if #added > 0 then
    local f = io.open(path, "w")
    if f then
      f:write(new)
      f:close()
    end
  end
  return added
end

--- After a document is written: open it, link it from AGENTS.md, say what happened
---@param root string
---@param file string
---@param path string
---@param replaced boolean
---@param extra string?
local function written(root, file, path, replaced, extra)
  vim.cmd.checktime()
  vim.cmd.edit(vim.fn.fnameescape(path))
  local msg = ("Setup: %s %s"):format(replaced and "rewrote" or "created", file)
  if replaced then
    msg = msg .. " (the previous one is in the trash: <leader>Fu)"
  end
  if file ~= "AGENTS.md" then
    local added = M.link(root)
    if #added > 0 then
      msg = msg .. "; linked from AGENTS.md"
    end
  end
  if file == "DESIGN.md" and exists(root .. "/SPEC.md") then -- the next step that pays off most: the screens drawn
    extra = (extra and (extra .. "; ") or "") .. "<leader>aSw draws the screens"
  end
  log.info(msg .. (extra and ("; " .. extra) or ""))
end

--- Runs `go(replace)` when the file is not there; when it is, asks first (`verb`: Replace, Update…). No means open it.
---@param root string
---@param file string
---@param verb string
---@param note string
---@param go fun(replace: boolean)
local function unless_there(root, file, verb, note, go)
  local path = root .. "/" .. file
  if not exists(path) then
    return go(false)
  end
  local modal = require "utils.modal"
  modal.confirm({
    { { shown(root, file), modal.hl.file }, { " is already there", modal.hl.muted } },
    { { note, modal.hl.muted } },
  }, {
    title = file,
    confirm = verb,
    on_cancel = function()
      vim.cmd.edit(vim.fn.fnameescape(path))
    end,
  }, function()
    go(true)
  end)
end

--- Sends a request and hands back the document's text (cleaned); warns about sections the answer left out
---@param req table
---@param id string
---@param done fun(text: string)
---@param failed fun()?
local function ask(req, id, done, failed)
  local file = compose.doc(id).file
  if busy[file] then
    return log.info("Setup: " .. file .. " is already being written")
  end
  local sel = require("agent.selection").current { name = req.action, tier = req.tier }
  if not sel then
    return log.warn "Setup: no agent backend found (<leader>am)"
  end
  busy[file] = true
  log.info(("Setup: writing %s with %s…"):format(file, require("agent.selection").label(sel)))
  require("agent").complete(req, function(ok, text)
    busy[file] = nil
    if not ok or vim.trim(text or "") == "" then
      log.warn(("Setup: %s was not written: %s"):format(file, ok and "empty answer" or text))
      return failed and failed()
    end
    local doc = compose.clean(text)
    local missing = compose.missing(doc, id)
    if #missing > 0 then
      log.warn(("Setup: %s came without %s"):format(file, table.concat(missing, ", ")))
    end
    done(doc)
  end)
end

-- ── AGENTS.md ────────────────────────────────────────────────────────────────

--- Written by the model from the project (an existing one is updated, keeping what is still true)
function M.agents()
  local root = snapshot.root()
  unless_there(
    root,
    "AGENTS.md",
    "Update",
    "The model reads it and the project, and keeps what is still true",
    function(replace)
      local facts = snapshot.collect(root)
      ask(require("agent.kit.prompts").agents(facts), "agents", function(text)
        local path, why = M.write(root, "AGENTS.md", text, replace)
        if not path then
          return log.warn("Setup: " .. why)
        end
        written(root, "AGENTS.md", path, replace, M.claude_hint(root))
      end)
    end
  )
end

--- From the project's facts and general rules, without a model
function M.agents_template()
  local root = snapshot.root()
  unless_there(
    root,
    "AGENTS.md",
    "Replace",
    "The template replaces it (the old one goes to the trash)",
    function(replace)
      local text = require("agent.kit.template").agents(snapshot.collect(root))
      local path, why = M.write(root, "AGENTS.md", text, replace)
      if not path then
        return log.warn("Setup: " .. why)
      end
      written(root, "AGENTS.md", path, replace, "fill in the TODO lines")
    end
  )
end

--- Claude Code reads CLAUDE.md, not AGENTS.md: what to say when it is missing or does not point there
---@param root string
---@return string?
function M.claude_hint(root)
  local text = require("utils.project").read(root .. "/CLAUDE.md")
  if not text then
    return "Claude Code reads CLAUDE.md: <leader>aSc links it"
  elseif not text:find("AGENTS.md", 1, true) then
    return "CLAUDE.md does not mention AGENTS.md: <leader>aSc links it"
  end
end

--- CLAUDE.md that imports AGENTS.md (`@AGENTS.md`), or that line added to the one there
function M.claude()
  local root = snapshot.root()
  local path = root .. "/CLAUDE.md"
  local text = require("utils.project").read(path)
  if text and text:find("AGENTS.md", 1, true) then
    log.info "Setup: CLAUDE.md already points to AGENTS.md"
    return vim.cmd.edit(vim.fn.fnameescape(path))
  end
  if unsaved(path) then
    return log.warn "Setup: CLAUDE.md has unsaved changes in a buffer"
  end
  local new = text and (text:gsub("%s+$", "") .. "\n\n@AGENTS.md\n")
    or "# CLAUDE.md\n\nThe instructions for this repository live in AGENTS.md (shared by every coding agent):\n\n@AGENTS.md\n"
  local f, err = io.open(path, "w")
  if not f then
    return log.warn("Setup: " .. tostring(err))
  end
  f:write(new)
  f:close()
  vim.cmd.checktime()
  vim.cmd.edit(vim.fn.fnameescape(path))
  log.info(
    ("Setup: %s CLAUDE.md (imports AGENTS.md)%s"):format(
      text and "updated" or "created",
      exists(root .. "/AGENTS.md") and "" or "; AGENTS.md is not there yet: <leader>aSa"
    )
  )
end

-- ── SPEC.md ──────────────────────────────────────────────────────────────────

--- Written in your words, reorganised by the model into the spec's sections. With a SPEC.md there, the page starts from it:
--- edit it freely and it comes back tidy (ids kept)
function M.spec()
  local root = snapshot.root()
  local path = root .. "/SPEC.md"
  local current = require("utils.project").read(path)
  require("agent.kit.draft").open({
    id = "spec",
    title = current and "SPEC.md · edit and tidy" or "SPEC.md · describe it",
    text = current,
    hint = current
        and {
          "This is the current SPEC.md: change anything, in any shape. Sending rewrites it tidy (the old one goes to the trash).",
        }
      or {
        "What are you building? Write it any way: problem, users, features, rules, screens, data, limits, doubts.",
        "It comes back as SPEC.md: requirements with acceptance criteria, and every gap as an open question.",
      },
  }, function(text)
    ask(require("agent.kit.prompts").spec(text, snapshot.collect(root)), "spec", function(doc)
      local replace = exists(path)
      local written_path, why = M.write(root, "SPEC.md", doc, replace)
      if not written_path then
        return log.warn("Setup: " .. why)
      end
      require("agent.kit.draft").forget "spec"
      local questions = doc:match "\n## Open questions\n(.-)\n## " or ""
      local n = select(2, questions:gsub("\n%s*[-*%d]", ""))
      written(root, "SPEC.md", written_path, replace, n > 0 and (n .. " open questions to answer") or nil)
    end)
  end)
end

-- ── STACK.md ─────────────────────────────────────────────────────────────────

--- The principles step: core ones checked (or `checked`), no descriptions; Esc goes back when `back` is given
---@param checked fun(p: KitPreset): boolean
---@param done fun(chosen: KitPreset[], ids: table<string, boolean>)
---@param back fun()?
local function pick_principles(checked, done, back)
  local list = presets.list "principles"
  require("utils.modal").checklist(
    vim.tbl_map(function(p)
      return { label = p.name, checked = checked(p) }
    end, list),
    {
      title = "Principles",
      clean = true,
      confirm = "Write",
      footer = "  space toggle · a all",
      on_cancel = back,
    },
    function(indexes)
      local chosen, ids = {}, {}
      for _, i in ipairs(indexes) do
        chosen[#chosen + 1] = list[i]
        ids[list[i].id] = true
      end
      done(chosen, ids)
    end
  )
end

--- Writes a STACK.md the text became, with its own message
---@param root string
---@param text string
---@param replace boolean
---@param extra string
local function write_stack(root, text, replace, extra)
  local path, why = M.write(root, "STACK.md", text, replace)
  if not path then
    return log.warn("Setup: " .. why)
  end
  written(root, "STACK.md", path, replace, extra)
end

---@class KitChoice
---@field key string          "pm:bun" or "<axis>/<id>"
---@field name string
---@field group string
---@field pm string?          package manager rewrite
---@field addon KitAddon?

--- What the customize step offers for a stack: another package manager (pnpm stacks), then the add-ons that fit
---@param text string
---@param tags table<string, boolean>
---@return KitChoice[]
local function choices(text, tags)
  local out = {}
  if compose.package_manager(text) == "pnpm" and not tags.monorepo then
    out[#out + 1] = { key = "pm:pnpm", name = "pnpm", group = "Package manager" }
    out[#out + 1] = { key = "pm:bun", name = "Bun", group = "Package manager", pm = "bun" }
    out[#out + 1] = { key = "pm:npm", name = "npm", group = "Package manager", pm = "npm" }
  end
  for _, a in ipairs(presets.addons(tags)) do
    out[#out + 1] = { key = a.axis .. "/" .. a.id, name = a.name, group = a.group, addon = a }
  end
  return out
end

--- Applies the checked choices to the text: the package manager first, then each add-on
---@param text string
---@param list KitChoice[]
---@param checked table<string, boolean>
---@return string, string[] names of what changed something
local function apply(text, list, checked)
  local names = {}
  for _, c in ipairs(list) do
    if checked[c.key] and (c.pm or c.addon) then
      text = c.pm and compose.use_package_manager(text, c.pm) or compose.merge(text, c.addon.body)
      names[#names + 1] = c.name
    end
  end
  return text, names
end

--- The customize step: one clean list in groups (one-of groups are radios), the best picks checked.
--- `checked` = what to start from (keys); `done(checked)` gets the new set; `back` makes Esc go to the step before.
---@param list KitChoice[]
---@param checked table<string, boolean>
---@param title string
---@param done fun(checked: table<string, boolean>)
---@param back fun()?
function M.customize(list, checked, title, done, back)
  if #list == 0 then
    return done {}
  end
  local exclusive = {}
  for _, c in ipairs(list) do
    exclusive[c.group] = c.group == "Package manager" or presets.exclusive(c.group)
  end
  require("utils.modal").checklist(
    vim.tbl_map(function(c)
      return { label = c.name, group = c.group, checked = checked[c.key] == true }
    end, list),
    {
      title = title,
      clean = true,
      exclusive = exclusive,
      confirm = "Next",
      footer = "  space toggle · a all",
      on_cancel = back,
    },
    function(indexes)
      local out = {}
      for _, i in ipairs(indexes) do
        out[list[i].key] = true
      end
      done(out)
    end
  )
end

--- The best picks for a stack: pnpm stays, and the add-ons whose `default:` names it (presets.preselect)
---@param list KitChoice[]
---@param tags table<string, boolean>
---@param id string
---@param category string?
---@return table<string, boolean>
local function best(list, tags, id, category)
  local addons = {}
  for _, c in ipairs(list) do
    if c.addon then
      addons[#addons + 1] = c.addon
    end
  end
  local picked = presets.preselect(addons, tags, id, category)
  local out = {}
  for _, c in ipairs(list) do
    if c.key == "pm:pnpm" or (c.addon and picked[c.addon]) then
      out[c.key] = true
    end
  end
  return out
end

--- "Go + chi · 6 add-ons · 7 principles"
---@param name string?
---@param addons string[]
---@param principles integer
---@return string
local function summary(name, addons, principles)
  local parts = { name }
  if #addons > 0 then
    parts[#parts + 1] = ("%d add-on%s"):format(#addons, #addons == 1 and "" or "s")
  end
  parts[#parts + 1] = ("%d principles"):format(principles)
  return table.concat(parts, " · ")
end

---@param list any[]
---@param pred fun(x: any): boolean
---@return integer?
local function index_of(list, pred)
  for i, x in ipairs(list) do
    if pred(x) then
      return i
    end
  end
end

--- A stack preset, in steps: kind of project → stack (preview) → customize → principles. Esc goes back one step and keeps
--- what was chosen there. `start` (from the library, `/`): begin at its customize step with that preset.
---@param start { preset: KitPreset, category: string }?
function M.stack(start)
  local root = snapshot.root()
  unless_there(root, "STACK.md", "Replace", "The preset replaces it (the old one goes to the trash)", function(replace)
    local picker = require "tasks.picker"
    local categories = presets.categories()
    local st = {} ---@type { category: table?, preset: KitPreset?, list: KitChoice[]?, checked: table?, principles: table? }
    local step_category, step_stack, step_customize, step_principles

    step_category = function()
      picker.choose(
        vim.tbl_map(function(c)
          return { label = c.label, value = c }
        end, categories),
        {
          title = "Stack",
          select = st.category and index_of(categories, function(c)
            return c.id == st.category.id
          end),
        },
        function(c)
          if not st.category or st.category.id ~= c.id then
            st.preset = nil
          end
          st.category = c
          step_stack()
        end
      )
    end

    step_stack = function()
      local list = presets.list("stack/" .. st.category.id)
      picker.choose(
        vim.tbl_map(function(p)
          return { label = p.name, path = p.path, value = p, search = p.id .. " " .. p.desc }
        end, list),
        {
          title = st.category.label,
          preview = true,
          select = st.preset and index_of(list, function(p)
            return p.id == st.preset.id
          end),
          on_cancel = #categories > 1 and step_category or nil,
        },
        function(p)
          if not st.preset or st.preset.id ~= p.id then -- another stack: its own best picks
            local tags = presets.tags(p, st.category.id)
            st.list = choices(p.body, tags)
            st.checked = best(st.list, tags, p.id, st.category.id)
          end
          st.preset = p
          step_customize()
        end
      )
    end

    step_customize = function()
      M.customize(st.list, st.checked, st.preset.name, function(checked)
        st.checked = checked
        step_principles()
      end, step_stack)
    end

    step_principles = function()
      pick_principles(function(p)
        if st.principles then
          return st.principles[p.id] == true
        end
        return p.core
      end, function(chosen, ids)
        st.principles = ids
        local text, names = apply(st.preset.body, st.list, st.checked)
        write_stack(root, compose.set_principles(text, chosen), replace, summary(st.preset.name, names, #chosen))
      end, function()
        if #st.list > 0 then
          step_customize()
        else
          step_stack()
        end
      end)
    end

    if start then
      st.category = vim.iter(categories):find(function(c)
        return c.id == start.category
      end) or categories[1]
      local tags = presets.tags(start.preset, start.category)
      st.list = choices(start.preset.body, tags)
      st.checked = best(st.list, tags, start.preset.id, start.category)
      st.preset = start.preset
      return step_customize()
    end
    if #categories == 1 then
      st.category = categories[1]
      return step_stack()
    end
    step_category()
  end)
end

--- Described in your words → customize (what fits the words you used, best picks checked) → principles → the model writes
--- it knowing the add-ons, and they are merged after. Esc goes back (to the page, with what you wrote).
function M.stack_prompt()
  local root = snapshot.root()
  unless_there(
    root,
    "STACK.md",
    "Replace",
    "What you describe replaces it (the old one goes to the trash)",
    function(replace)
      local st = {} ---@type { description: string?, list: KitChoice[]?, checked: table?, principles: table? }
      local step_draft, step_customize, step_principles

      step_draft = function()
        require("agent.kit.draft").open({
          id = "stack",
          title = "STACK.md · describe it",
          hint = {
            "The project and the stack you want: kind (API, web, mobile, TUI, self-hosted…), language, frameworks,",
            "data, auth, deploy, scale. Unsure parts are fine: the model picks mature options and says why.",
          },
        }, function(description)
          if st.description ~= description then
            local tags = presets.tags({ id = "described", body = description }, nil)
            st.list = vim.tbl_filter(function(c)
              return c.addon ~= nil -- the model chooses the package manager from what you wrote
            end, choices("", tags))
            st.checked = best(st.list, tags, "described", nil)
          end
          st.description = description
          step_customize()
        end)
      end

      step_customize = function()
        M.customize(st.list, st.checked, "Your stack", function(checked)
          st.checked = checked
          step_principles()
        end, step_draft)
      end

      step_principles = function()
        pick_principles(function(p)
          if st.principles then
            return st.principles[p.id] == true
          end
          return p.core
        end, function(chosen, ids)
          st.principles = ids
          local addon_names = {}
          for _, c in ipairs(st.list) do
            if st.checked[c.key] then
              addon_names[#addon_names + 1] = c.name
            end
          end
          local names = vim.tbl_map(function(p)
            return p.name
          end, chosen)
          local req = require("agent.kit.prompts").stack(st.description, names, snapshot.collect(root), addon_names)
          ask(req, "stack", function(doc)
            local text = apply(doc, st.list, st.checked)
            require("agent.kit.draft").forget "stack"
            write_stack(root, compose.set_principles(text, chosen), replace, summary(nil, addon_names, #chosen))
          end)
        end, function()
          if #st.list > 0 then
            step_customize()
          else
            step_draft()
          end
        end)
      end

      step_draft()
    end
  )
end

--- Adds add-ons to the STACK.md there (those already in it come checked; unchecking one does not take it out)
function M.stack_customize()
  local root = snapshot.root()
  local path = root .. "/STACK.md"
  local text = require("utils.project").read(path)
  if not text then
    return log.info "Setup: there is no STACK.md yet (<leader>aSt from a preset, <leader>aST described)"
  end
  if unsaved(path) then
    return log.warn "Setup: STACK.md has unsaved changes in a buffer: save them first"
  end
  local tags = presets.tags({ id = "stack", body = text }, nil)
  local list = vim.tbl_filter(function(c)
    return c.addon ~= nil or c.key == "pm:pnpm" or c.pm ~= nil
  end, choices(text, tags))
  local checked = {}
  for _, c in ipairs(list) do
    checked[c.key] = c.key == "pm:pnpm" or (c.addon ~= nil and compose.applied(text, c.addon.body))
  end
  if #list == 0 then
    return log.info "Setup: no add-ons fit this STACK.md"
  end
  M.customize(list, checked, "STACK.md", function(new_checked)
    local new, names = apply(text, list, new_checked)
    if new == text then
      return log.info "Setup: STACK.md already has all of that"
    end
    local f, err = io.open(path, "w")
    if not f then
      return log.warn("Setup: " .. tostring(err))
    end
    f:write(new)
    f:close()
    vim.cmd.checktime()
    vim.cmd.edit(vim.fn.fnameescape(path))
    log.info("Setup: STACK.md · " .. table.concat(names, ", "))
  end)
end

-- ── DESIGN.md ────────────────────────────────────────────────────────────────

--- What the DESIGN.md customize step offers: the design add-ons that fit (platforms, theme, palette, motion, effects…)
---@param tags table<string, boolean>
---@return KitChoice[]
local function design_choices(tags)
  return vim.tbl_map(function(a)
    return { key = a.axis .. "/" .. a.id, name = a.name, group = a.group, addon = a }
  end, presets.addons(tags, nil, "design"))
end

--- A design's tags plus the project's STACK.md's (its language picks the toolkit add-on: Go → Charm, Rust → Ratatui…)
---@param preset KitPreset|{ id: string }
---@param category string?
---@return table<string, boolean>
local function design_tags(preset, category)
  local stack = require("utils.project").read(snapshot.root() .. "/STACK.md")
  return presets.with_stack(presets.design_tags(preset, category), stack)
end

--- Words that make a description a terminal one
local TERMINAL_WORDS = { "terminal", "tui", "cli", "console", "ascii", "braille", "ansi", "shell" }

--- The tags of a free description: terminal or not, plus those of a design it names (its base)
---@param text string
---@param base KitPreset?
---@return table<string, boolean>, string?
local function described_design_tags(text, base)
  if base then
    return design_tags(base, base.category), base.category
  end
  local words = " " .. text:lower():gsub("[^%w]", " ") .. " "
  for _, w in ipairs(TERMINAL_WORDS) do
    if words:find(" " .. w .. " ", 1, true) then
      return design_tags({ id = "described" }, "terminal"), "terminal"
    end
  end
  return design_tags({ id = "described" }, "styles"), "styles"
end

--- A design preset, in steps: kind (design systems, styles, terminal / TUI) → design (preview) → customize (platforms,
--- theme, palette, motion, effects, glyphs, density, accessibility; the best picks checked). Esc goes back one step.
---@param start { preset: KitPreset, category: string }?
function M.design(start)
  local root = snapshot.root()
  unless_there(root, "DESIGN.md", "Replace", "The preset replaces it (the old one goes to the trash)", function(replace)
    local picker = require "tasks.picker"
    local categories = presets.categories(nil, "design")
    local st = {} ---@type { category: table?, preset: KitPreset?, list: KitChoice[]?, checked: table? }
    local step_category, step_design, step_customize

    step_category = function()
      picker.choose(
        vim.tbl_map(function(c)
          return { label = c.label, value = c }
        end, categories),
        {
          title = "Design",
          select = st.category and index_of(categories, function(c)
            return c.id == st.category.id
          end),
        },
        function(c)
          if not st.category or st.category.id ~= c.id then
            st.preset = nil
          end
          st.category = c
          step_design()
        end
      )
    end

    step_design = function()
      local list = presets.list("design/" .. st.category.id)
      picker.choose(
        vim.tbl_map(function(p)
          return { label = p.name, path = p.path, value = p, search = p.id .. " " .. p.desc }
        end, list),
        {
          title = st.category.label,
          preview = true,
          select = st.preset and index_of(list, function(p)
            return p.id == st.preset.id
          end),
          on_cancel = #categories > 1 and step_category or nil,
        },
        function(p)
          if not st.preset or st.preset.id ~= p.id then
            local tags = design_tags(p, st.category.id)
            st.list = design_choices(tags)
            st.checked = best(st.list, tags, p.id, st.category.id)
          end
          st.preset = p
          step_customize()
        end
      )
    end

    step_customize = function()
      M.customize(st.list, st.checked, st.preset.name, function(checked)
        st.checked = checked
        local text, names = apply(st.preset.body, st.list, checked)
        local path, why = M.write(root, "DESIGN.md", text, replace)
        if not path then
          return log.warn("Setup: " .. why)
        end
        written(root, "DESIGN.md", path, replace, (summary(st.preset.name, names, 0):gsub(" · 0 principles", "")))
      end, step_design)
    end

    if start then
      st.category = vim.iter(categories):find(function(c)
        return c.id == start.category
      end) or categories[1]
      local tags = design_tags(start.preset, start.category)
      st.list = design_choices(tags)
      st.checked = best(st.list, tags, start.preset.id, start.category)
      st.preset = start.preset
      return step_customize()
    end
    if #categories == 1 then
      st.category = categories[1]
      return step_design()
    end
    step_category()
  end)
end

--- Described in your words ("like Linear, warmer, for a logistics dashboard"; "a braille TUI with amber phosphor") →
--- customize → the model writes it knowing the add-ons, which are merged after. A design it names is sent as the base.
function M.design_prompt()
  local root = snapshot.root()
  local all = presets.all "design"
  local names = vim.tbl_map(function(p)
    return p.name
  end, all)
  unless_there(
    root,
    "DESIGN.md",
    "Replace",
    "What you describe replaces it (the old one goes to the trash)",
    function(replace)
      local st = {} ---@type { description: string?, base: KitPreset?, list: KitChoice[]?, checked: table? }
      local step_draft, step_customize

      step_draft = function()
        require("agent.kit.draft").open({
          id = "design",
          title = "DESIGN.md · describe it",
          hint = {
            "The look and feel: product, audience, mood, density, light/dark, colors, fonts; GUI, mobile or terminal.",
            "Name a design to start from and what to change (Linear, Material 3, Braille, ASCII art, Retro CRT…).",
          },
        }, function(description)
          if st.description ~= description then
            st.base = compose.named(description, all)
            local tags, category = described_design_tags(description, st.base)
            st.list = design_choices(tags)
            st.checked = best(st.list, tags, st.base and st.base.id or "described", category)
          end
          st.description = description
          step_customize()
        end)
      end

      step_customize = function()
        M.customize(st.list, st.checked, "Your design", function(checked)
          st.checked = checked
          local addon_names = {}
          for _, c in ipairs(st.list) do
            if checked[c.key] then
              addon_names[#addon_names + 1] = c.name
            end
          end
          local req = require("agent.kit.prompts").design(st.description, st.base, names, addon_names)
          ask(req, "design", function(doc)
            local text = apply(doc, st.list, checked)
            local path, why = M.write(root, "DESIGN.md", text, replace)
            if not path then
              return log.warn("Setup: " .. why)
            end
            require("agent.kit.draft").forget "design"
            written(root, "DESIGN.md", path, replace, st.base and ("based on " .. st.base.name) or nil)
          end)
        end, step_draft)
      end

      step_draft()
    end
  )
end

--- The `## Screens` section of a model's answer: what comes before its heading and a fence around it dropped; nil if absent
---@param text string
---@return string?
function M.screens_of(text)
  text = "\n" .. (text or "")
  local at = text:find "\n##%s+[Ss]creens"
  if not at then
    return nil
  end
  at = at + 1
  local body = vim.trim(text:sub(at))
  if text:sub(1, at - 1):match "```%w*%s*$" then -- the whole answer was fenced: its closing fence goes
    body = vim.trim((body:gsub("\n```%s*$", "")))
  end
  return body
end

--- <leader>aSw: a wireframe of every main screen SPEC.md names, drawn in DESIGN.md's style, written into DESIGN.md as its
--- `## Screens` section (replaced when there is one; the previous DESIGN.md goes to the trash). Needs both documents.
function M.screens()
  local root = snapshot.root()
  local project = require "utils.project"
  local spec, design = project.read(root .. "/SPEC.md"), project.read(root .. "/DESIGN.md")
  if not design or not spec then
    return log.info(
      ("Setup: screens are drawn from SPEC.md in DESIGN.md's style: missing %s (<leader>aS%s)"):format(
        design and "SPEC.md" or "DESIGN.md",
        design and "s" or "d"
      )
    )
  end
  if unsaved(root .. "/DESIGN.md") then
    return log.warn "Setup: DESIGN.md has unsaved changes in a buffer: save them first"
  end
  if busy["DESIGN.md"] then
    return log.info "Setup: DESIGN.md is already being written"
  end
  local req = require("agent.kit.prompts").screens(spec, design, project.read(root .. "/STACK.md"))
  local sel = require("agent.selection").current { name = req.action, tier = req.tier }
  if not sel then
    return log.warn "Setup: no agent backend found (<leader>am)"
  end
  busy["DESIGN.md"] = true
  log.info(("Setup: drawing the screens with %s…"):format(require("agent.selection").label(sel)))
  require("agent").complete(req, function(ok, text)
    busy["DESIGN.md"] = nil
    local screens = ok and M.screens_of(text)
    if not screens then
      return log.warn("Setup: no screens drawn: " .. (ok and "the answer had no ## Screens section" or tostring(text)))
    end
    local current = project.read(root .. "/DESIGN.md") or design
    local path, why = M.write(root, "DESIGN.md", compose.set_screens(current, screens), true)
    if not path then
      return log.warn("Setup: " .. why)
    end
    vim.cmd.checktime()
    vim.cmd.edit(vim.fn.fnameescape(path))
    vim.fn.search("^## Screens", "w")
    local n = select(2, screens:gsub("\n### ", ""))
    log.info(
      ("Setup: DESIGN.md · %d screen%s drawn (the previous one is in the trash: <leader>Fu)"):format(
        n,
        n == 1 and "" or "s"
      )
    )
  end)
end

--- Changes which principles the STACK.md there carries (the section is rebuilt from the presets)
function M.principles()
  local root = snapshot.root()
  local path = root .. "/STACK.md"
  local text = require("utils.project").read(path)
  if not text then
    return log.info "Setup: there is no STACK.md yet (<leader>aSt from a preset, <leader>aST described)"
  end
  if unsaved(path) then
    return log.warn "Setup: STACK.md has unsaved changes in a buffer: save them first"
  end
  local present = {}
  for _, name in ipairs(compose.principles_in(text)) do
    present[name:lower()] = true
  end
  pick_principles(function(p)
    return present[p.name:lower()] == true
  end, function(chosen)
    local f, err = io.open(path, "w")
    if not f then
      return log.warn("Setup: " .. tostring(err))
    end
    f:write(compose.set_principles(text, chosen))
    f:close()
    vim.cmd.checktime()
    vim.cmd.edit(vim.fn.fnameescape(path))
    log.info(("Setup: STACK.md carries %d principles"):format(#chosen))
  end)
end

--- <leader>aS/: every preset in one search (use, embed, copy, open): agent/kit/library.lua
function M.find()
  require("agent.kit.library").open()
end

-- ── Overview ─────────────────────────────────────────────────────────────────

--- The documents, which are there, and Enter opens one (or starts writing it)
function M.overview()
  local root = snapshot.root()
  local start = {
    agents = M.agents,
    stack = M.stack,
    design = M.design,
    spec = M.spec,
  }
  local keys = { agents = "a (A: template)", stack = "t (T: described)", design = "d (D: described)", spec = "s" }
  local cache = vim.fn.stdpath "cache" .. "/agent-kit"
  vim.fn.mkdir(cache, "p")
  local items = {}
  for _, d in ipairs(compose.DOCS) do
    local path = root .. "/" .. d.file
    local there = exists(path)
    local preview = path
    if not there then -- the previewer needs a file: one saying what is missing (it would fall back to the entry's table)
      preview = cache .. "/" .. d.file
      local f = io.open(preview, "w")
      if f then
        f:write(("# %s is missing\n\n%s.\n\nEnter starts it; or <leader>aS%s.\n"):format(d.file, d.about, keys[d.id]))
        f:close()
      end
    end
    items[#items + 1] = {
      label = (there and "● " or "○ ") .. d.file,
      desc = there and d.about or ("missing: " .. d.about),
      path = preview,
      value = { path = path, there = there, start = start[d.id] },
    }
  end
  require("tasks.picker").choose(
    items,
    { title = "Agent documents · " .. vim.fn.fnamemodify(root, ":~"), preview = true },
    function(v)
      if v.there then
        vim.cmd.edit(vim.fn.fnameescape(v.path))
      else
        v.start()
      end
    end
  )
end

return M
