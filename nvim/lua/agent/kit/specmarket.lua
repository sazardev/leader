-- ── SPEC.md modules, as a small marketplace (<leader>aSm) ────────────────────
-- The whole screen: the modules by group on the left, the one under the cursor on the right (what it is, its
-- requirements with their criteria, edge cases, the questions that are yours), and under both what SPEC.md would get from
-- the choice (modules, FR range, counts, what came in because another needs it). Nothing is written until you add:
--   list    j k move · Space pick · ⏎ read and customize · p what SPEC.md gets · / filter · { } group · A add · q close
--   read    j k scroll · Space keep or leave out the requirement under the cursor · p what SPEC.md gets · Esc back
--   result  the text that would be added to SPEC.md, as it would read · Esc back
-- The text work is `specmodules.plan` (pure); this file is the model of the view (pure, tested) and its windows.
local market = require "utils.market"
local modules = require "agent.kit.specmodules"
local modal = require "utils.modal"

local M = {}

---@class MarketState
---@field root string
---@field spec string
---@field all SpecModule[]
---@field kits SpecKit[]
---@field labels { axes: table<string, string>, patterns: table<string, string> } names for the `tech`/`design` hints
---@field applied table<string, boolean>
---@field chosen table<string, boolean>
---@field left_out table<string, table<string, boolean>>
---@field hide_done boolean   leave out what SPEC.md already has
---@field suggested table<string, string> key → the word of SPEC.md that names it

---@class MarketRow
---@field group string?       a group title row
---@field title string?       the header at the top of the list
---@field spacer boolean?     air between two groups
---@field module SpecModule?
---@field kit SpecKit?
---@field state "in"|"chosen"|"pulled"|"partial"|"off"?
---@field suggested string?   the word of SPEC.md that names this module
---@field collapsed boolean?  a group title whose rows are folded away

-- ── pure: what the view shows ────────────────────────────────────────────────

M.wrap = market.wrap

---@param st { all: SpecModule[], applied: table<string, boolean>, chosen: table<string, boolean>, left_out: table, filter: string? }
---@return string[] chosen keys in catalog order, table<string, boolean> pulled keys
local function picked(st)
  local keys = {}
  for _, m in ipairs(st.all) do
    local key = modules.key(m)
    if st.chosen[key] and not st.applied[key] then
      keys[#keys + 1] = key
    end
  end
  local pulled = {}
  local _, extra = modules.resolve(keys, st.all, st.applied)
  for _, k in ipairs(extra) do
    pulled[k] = true
  end
  return keys, pulled
end

--- Where a kit stands: every module it brings is in SPEC.md, picked, some picked, or none
---@param st { all: SpecModule[], applied: table<string, boolean>, chosen: table<string, boolean> }
---@param kit SpecKit
---@return "in"|"chosen"|"partial"|"off"
function M.kit_state(st, kit)
  local exists = {}
  for _, m in ipairs(st.all) do
    exists[modules.key(m)] = true
  end
  local todo, picked_n = 0, 0
  for _, key in ipairs(kit.modules) do
    if exists[key] and not st.applied[key] then
      todo = todo + 1
      picked_n = picked_n + (st.chosen[key] and 1 or 0)
    end
  end
  return (todo == 0 and "in") or (picked_n == todo and "chosen") or (picked_n > 0 and "partial") or "off"
end

--- The text a filter looks in: names, descriptions, requirement titles, and what the module pairs with
---@param m SpecModule
---@return string
local function haystack(m)
  local titles = vim.tbl_map(function(r)
    return r.title
  end, m.requirements)
  return table.concat(
    vim.list_extend({ m.name, m.desc, modules.key(m), table.concat(m.tech, " "), table.concat(m.design, " ") }, titles),
    " "
  ):lower()
end

--- The list: the starter kits, then the modules by group (each with its state), narrowed by the filter
---@param st table see picked
---@return MarketRow[]
function M.rows(st)
  local labels = {}
  for _, g in ipairs(modules.GROUPS) do
    labels[g.id] = g.label
  end
  local _, pulled = picked(st)
  local needle = vim.trim(st.filter or ""):lower()
  local rows, group = { { title = "SPEC.md MODULES" }, { spacer = true } }, nil
  local kit_rows = {}
  for _, kit in ipairs(st.kits or {}) do
    local hay = (kit.name .. " " .. kit.desc .. " " .. table.concat(kit.modules, " ") .. " " .. table.concat(kit.stacks, " ")):lower()
    local state = M.kit_state(st, kit)
    if (needle == "" or hay:find(needle, 1, true)) and not (st.hide_done and state == "in") then
      kit_rows[#kit_rows + 1] = { kit = kit, state = state }
    end
  end
  if #kit_rows > 0 then
    rows[#rows + 1] = { group = "Starter kits" }
    vim.list_extend(rows, kit_rows)
    group = "kits"
  end
  for _, m in ipairs(st.all) do
    local key = modules.key(m)
    if (needle == "" or haystack(m):find(needle, 1, true)) and not (st.hide_done and st.applied[key]) then
      if m.group ~= group then
        if group then
          rows[#rows + 1] = { spacer = true }
        end
        group = m.group
        rows[#rows + 1] = { group = labels[m.group] or m.group }
      end
      rows[#rows + 1] = {
        module = m,
        state = st.applied[key] and "in" or st.chosen[key] and "chosen" or pulled[key] and "pulled" or "off",
        suggested = not st.applied[key] and st.suggested and st.suggested[key] or nil,
      }
    end
  end
  return rows
end

local MARK = { ["in"] = "✓", chosen = "■", pulled = "+", partial = "◧", off = "□" }

--- One list row as the view draws it
---@param row MarketRow
---@return MarketLine
function M.list_line(row)
  if row.title then
    return { { "  " .. row.title, modal.hl.key } }
  elseif row.spacer then
    return { { "" } }
  elseif row.group then
    return { { (row.collapsed and "▸ " or "  ") .. row.group:upper(), modal.hl.muted } }
  end
  local state = row.state --[[@as string]]
  local name = row.module and row.module.name or row.kit.name
  local lit = state == "chosen" or state == "pulled" or state == "partial"
  return {
    { " " .. MARK[state] .. " ", (state == "chosen" or state == "partial") and modal.hl.mark or modal.hl.muted },
    { name, lit and modal.hl.file or modal.hl.muted },
    { row.suggested and state == "off" and "  ★" or "", modal.hl.mark },
  }
end

--- "STACK.md add-ons: Auth, Database" / "DESIGN.md patterns: Forms and validation" / "Usually on: nextjs, t3" as pane lines
---@param tech string[]
---@param design string[]
---@param stacks string[]?
---@param labels { axes: table<string, string>, patterns: table<string, string> }?
---@param width integer
---@return MarketLine[]
local function pairs_with(tech, design, stacks, labels, width)
  labels = labels or { axes = {}, patterns = {} }
  local out = {}
  local function row(title, names)
    if #names == 0 then
      return
    end
    for _, text in ipairs(M.wrap(title .. ": " .. table.concat(names, ", "), width)) do
      out[#out + 1] = { { "  " .. text, modal.hl.muted } }
    end
  end
  row("STACK.md add-ons", vim.tbl_map(function(t)
    return labels.axes[t] or t
  end, tech))
  row("DESIGN.md patterns", vim.tbl_map(function(d)
    return labels.patterns[d] or d
  end, design))
  row("Usually built on", stacks or {})
  if #out > 0 then
    table.insert(out, 1, { { "  GOES WITH (the library has them: <leader>aSt and <leader>aSd)", modal.hl.muted } })
    out[#out + 1] = { { "" } }
  end
  return out
end

--- A starter kit as the right pane reads it
---@param kit SpecKit
---@param opts { width: integer, state: string, by_key: table<string, SpecModule>, applied: table<string, boolean>, chosen: table<string, boolean>, labels: table? }
---@return MarketLine[]
function M.kit_detail(kit, opts)
  local width = opts.width - 4
  local lines = { { { "  " .. kit.name:upper(), modal.hl.key } } }
  for _, row in ipairs(M.wrap(kit.desc, width)) do
    lines[#lines + 1] = { { "  " .. row, modal.hl.muted } }
  end
  lines[#lines + 1] = { { "" } }
  for _, para in ipairs(vim.split(vim.trim(kit.body), "\n", { plain = true })) do
    if vim.trim(para) == "" then
      lines[#lines + 1] = { { "" } }
    else
      local bullet = para:match "^%s*[-*]%s+(.+)$"
      for i, row in ipairs(M.wrap((bullet or para):gsub("%*%*", ""), width - (bullet and 2 or 0))) do
        lines[#lines + 1] = { { "  " .. (bullet and (i == 1 and "· " or "  ") or "") .. row, bullet and modal.hl.muted or modal.hl.file } }
      end
    end
  end
  lines[#lines + 1] = { { "" } }
  lines[#lines + 1] = { { ("  MODULES (%d)  Space picks them all, ⏎ goes to the first"):format(#kit.modules), modal.hl.muted } }
  for _, key in ipairs(kit.modules) do
    local m = opts.by_key[key]
    if m then
      local state = opts.applied[key] and "in" or opts.chosen[key] and "chosen" or "off"
      lines[#lines + 1] = {
        { "  " .. MARK[state] .. " ", state == "chosen" and modal.hl.mark or modal.hl.muted },
        { m.name, state == "off" and modal.hl.muted or modal.hl.file },
        { "  " .. #m.requirements .. " req · " .. #m.questions .. " q", modal.hl.muted },
      }
    end
  end
  lines[#lines + 1] = { { "" } }
  vim.list_extend(lines, pairs_with(kit.tech, kit.design, kit.stacks, opts.labels, width))
  return lines
end

--- A module as the right pane reads it. `rows[i]` is the requirement title line i belongs to (for Space), if any
---@param module SpecModule
---@param opts { width: integer, state: string, left_out: table<string, boolean>?, labels: table?, suggested: string? }
---@return MarketLine[] lines, table<integer, string> rows
function M.detail(module, opts)
  local width = opts.width - 4
  local left_out = opts.left_out or {}
  local lines, rows = {}, {}
  local function add(line, req)
    lines[#lines + 1] = line
    if req then
      rows[#lines] = req
    end
  end
  local function para(text, hl, indent, req)
    for _, row in ipairs(M.wrap(text, width - #indent)) do
      add({ { "  " .. indent .. row, hl } }, req)
    end
  end

  add { { "  " .. module.name:upper(), modal.hl.key } }
  para(module.desc, modal.hl.muted, "")
  local facts = {}
  if opts.state == "in" then
    facts[#facts + 1] = "already in SPEC.md"
  elseif opts.state == "chosen" then
    facts[#facts + 1] = "picked"
  elseif opts.state == "pulled" then
    facts[#facts + 1] = "comes with what you picked"
  end
  if opts.suggested and opts.state == "off" then
    facts[#facts + 1] = ("★ your SPEC.md mentions «%s»"):format(opts.suggested)
  end
  if #module.needs > 0 then
    facts[#facts + 1] = "builds on " .. table.concat(module.needs, ", ")
  end
  if #facts > 0 then
    para(table.concat(facts, " · "), modal.hl.muted, "")
  end
  add { { "" } }
  for _, line in ipairs(pairs_with(module.tech, module.design, nil, opts.labels, width)) do
    add(line)
  end

  add { { ("  REQUIREMENTS (%d)"):format(#module.requirements), modal.hl.muted } }
  for _, r in ipairs(module.requirements) do
    local out = left_out[r.title]
    add({ { out and "  □ " or "  ■ ", out and modal.hl.muted or modal.hl.mark }, { r.title, out and modal.hl.muted or modal.hl.file } }, r.title)
    para(r.statement, modal.hl.muted, "    ", r.title)
    for _, c in ipairs(r.criteria) do
      para("· " .. c, modal.hl.muted, "      ", r.title)
    end
    add({ { "" } }, r.title)
  end
  if #module.edge_cases > 0 then
    add { { "  EDGE CASES (kept as written)", modal.hl.muted } }
    for _, x in ipairs(module.edge_cases) do
      para((x.req and ("[" .. x.req .. "] ") or "") .. x.text, modal.hl.muted, "  ", x.req)
    end
    add { { "" } }
  end
  if #module.questions > 0 then
    add { { "  QUESTIONS THAT ARE YOURS (never invented)", modal.hl.muted } }
    for _, x in ipairs(module.questions) do
      para("? " .. (x.req and ("[" .. x.req .. "] ") or "") .. x.text, modal.hl.muted, "  ", x.req)
    end
  end
  return lines, rows
end

--- What the choice does to SPEC.md, for the strip under the panes
---@param plan { list: SpecModule[], pulled: string[], result: SpecModuleResult }
---@param picked_n integer how many modules the user picked
---@return MarketLine[]
function M.summary(plan, picked_n)
  local r = plan.result
  local lines = { { { "  SPEC.md GETS", modal.hl.key } } }
  if picked_n == 0 then
    lines[#lines + 1] = { { "  Nothing picked yet: Space on a module picks it, ⏎ reads it first", modal.hl.muted } }
    return lines
  end
  local names = vim.tbl_map(function(m)
    return m.name
  end, plan.list)
  local shown, width = {}, 0
  for i, name in ipairs(names) do -- as many as fit on one line, then "+N more"
    width = width + vim.fn.strdisplaywidth(name) + 3
    if width > vim.o.columns - 16 and i < #names then
      shown[#shown + 1] = ("+%d more"):format(#names - i + 1)
      break
    end
    shown[#shown + 1] = name
  end
  lines[#lines + 1] = { { "  " .. table.concat(shown, " · "), modal.hl.file } }
  if #r.ids == 0 and r.edge == 0 and r.questions == 0 then
    lines[#lines + 1] = { { "  SPEC.md already has all of that", modal.hl.muted } }
    return lines
  end
  local range = #r.ids == 0 and "no new requirement"
    or (#r.ids == 1 and r.ids[1] or (r.ids[1] .. "–" .. r.ids[#r.ids]))
  lines[#lines + 1] = {
    {
      ("  %s · %d requirement%s · %d edge case%s · %d question%s for you"):format(
        range,
        #r.ids,
        #r.ids == 1 and "" or "s",
        r.edge,
        r.edge == 1 and "" or "s",
        r.questions,
        r.questions == 1 and "" or "s"
      ),
      modal.hl.muted,
    },
  }
  if #plan.pulled > 0 then
    lines[#lines + 1] = { { "  with what they need: " .. table.concat(plan.pulled, ", "), modal.hl.muted } }
  end
  if #r.skipped > 0 then
    lines[#lines + 1] = { { "  already in SPEC.md, kept as you wrote it: " .. table.concat(r.skipped, ", "), modal.hl.muted } }
  end
  return lines
end


-- ── the marketplace ──────────────────────────────────────────────────────────

---@param st MarketState
---@return table plan, integer picked
local function plan_of(st)
  local keys = picked(st)
  return modules.plan(st.spec, st.all, keys, st.left_out), #keys
end

---@param st MarketState
---@param key string
local function toggle_module(st, key)
  if st.applied[key] then
    return
  end
  st.chosen[key] = not st.chosen[key] or nil
  st.left_out[key] = nil
end

--- Opens the marketplace
---@param opts { root: string, spec: string, all: SpecModule[], kits: SpecKit[]?, labels: table?, pick: string[]?, applied: table<string, boolean>, on_add: fun(plan: table, st: MarketState) }
---@return MarketState
function M.new(opts)
  ---@type MarketState
  local st = {
    root = opts.root,
    spec = opts.spec,
    all = opts.all,
    kits = opts.kits or {},
    labels = opts.labels or { axes = {}, patterns = {} },
    applied = opts.applied,
    chosen = {},
    left_out = {},
    hide_done = false,
    suggested = modules.suggest(opts.spec, opts.all, opts.applied),
  }
  for _, key in ipairs(opts.pick or {}) do -- opened from a kit or a module of the library: already picked
    toggle_module(st, key)
  end

  local function toggle(m, row)
    if row and row.module then
      toggle_module(m, modules.key(row.module))
    elseif row and row.kit then -- a kit: all its modules, or none when they are all picked already
      local on = row.state ~= "chosen"
      for _, key in ipairs(row.kit.modules) do
        if on ~= (m.chosen[key] == true) then
          toggle_module(m, key)
        end
      end
    end
    market.refresh(m)
  end
  --- Space in the reading pane: the requirement under the cursor stays in or out; every one out = the module is not picked
  local function keep(m, row)
    local module = row and row.module
    local title = m.pane_rows[vim.api.nvim_win_get_cursor(m.wins.pane)[1]]
    if not module or not title or m.view ~= "pane" then
      return
    end
    local key = modules.key(module)
    if m.applied[key] then
      return
    end
    local out = m.left_out[key] or {}
    out[title] = not out[title] or nil
    m.left_out[key] = next(out) and out or nil
    local kept = 0
    for _, r in ipairs(module.requirements) do
      kept = kept + (out[r.title] and 0 or 1)
    end
    m.chosen[key] = kept > 0 or nil -- touching a requirement picks the module; leaving every one out drops it
    if kept == 0 then
      m.left_out[key] = nil
    end
    market.refresh(m)
  end
  --- What the picked modules go with (or the module / kit under the cursor when none is picked): the STACK.md add-on axes
  --- and the DESIGN.md patterns, and who says so
  local function pairing(m, row)
    local tech, design, names = {}, {}, {}
    local function take(item)
      for _, t in ipairs(item.tech) do
        if not vim.tbl_contains(tech, t) then
          tech[#tech + 1] = t
        end
      end
      for _, d in ipairs(item.design) do
        if not vim.tbl_contains(design, d) then
          design[#design + 1] = d
        end
      end
    end
    local keys = picked(m)
    if #keys > 0 then
      for _, mod in ipairs(m.all) do
        if vim.tbl_contains(keys, modules.key(mod)) then
          take(mod)
        end
      end
      return tech, design, "the modules you picked"
    end
    local item = row and (row.module or row.kit)
    if item then
      take(item)
      names[#names + 1] = item.name
    end
    return tech, design, names[1]
  end
  local function to_stack(m, row)
    local tech, _, why = pairing(m, row)
    if #tech == 0 then
      return require("utils.log").info "Setup: nothing in the STACK.md library goes with this"
    end
    require("agent.kit").stack_customize { focus = tech, why = why, keep_window = true, root = m.root }
  end
  local function to_design(m, row)
    local _, design, why = pairing(m, row)
    if #design == 0 then
      return require("utils.log").info "Setup: no screen pattern goes with this"
    end
    require("agent.kit").design_customize { pick = design, why = why, keep_window = true, root = m.root }
  end
  local function add(m)
    local plan, n = plan_of(m)
    if n == 0 then
      return require("utils.log").info "Setup: pick a module first (Space)"
    end
    opts.on_add(plan, m)
  end

  return market.new({
    title = "SPEC.md modules",
    summary_rows = 7,
    rows = M.rows,
    selectable = function(row)
      return row.module ~= nil or row.kit ~= nil
    end,
    list_line = M.list_line,
    pane = function(m, row, width)
      if row and row.kit then
        local by_key = {}
        for _, mod in ipairs(m.all) do
          by_key[modules.key(mod)] = mod
        end
        return M.kit_detail(row.kit, {
          width = width,
          state = row.state --[[@as string]],
          by_key = by_key,
          applied = m.applied,
          chosen = m.chosen,
          labels = m.labels,
        })
      elseif row and row.module then
        return M.detail(row.module, {
          width = width,
          state = row.state or "off",
          left_out = m.left_out[modules.key(row.module)],
          labels = m.labels,
          suggested = row.suggested,
        })
      end
      return { { { "" } } }, {}
    end,
    result = function(m)
      local plan = plan_of(m)
      local lines = { { { "  WHAT SPEC.md GETS", modal.hl.key } }, { { "" } } }
      local added = modules.added_lines(m.spec, plan.spec)
      if #added == 0 then
        lines[#lines + 1] = { { "  Nothing: pick a module first (Esc back)", modal.hl.muted } }
      end
      for _, l in ipairs(added) do
        lines[#lines + 1] = { { "  " .. l, l:match "^#" and modal.hl.file or modal.hl.muted } }
      end
      return lines
    end,
    summary = function(m)
      local plan, n = plan_of(m)
      return M.summary(plan, n)
    end,
    hints = function(m, mode)
      local row = market.current(m)
      if mode == "result" then
        return { { "Esc", "back" }, { "A", "add to SPEC.md" } }
      elseif mode == "pane" and row and row.kit then
        return { { "Esc", "back" }, { "t", "stack" }, { "d", "design" }, { "A", "add" }, { "?", "keys" } }
      elseif mode == "pane" then
        return { { "Space", "keep / leave out" }, { "p", "what SPEC.md gets" }, { "Esc", "back" }, { "A", "add" }, { "?", "keys" } }
      end
      return {
        { "Space", "pick" },
        { "⏎", "read" },
        { "p", "what SPEC.md gets" },
        { "t", "stack" },
        { "d", "design" },
        { "A", "add" },
        { "?", "keys" },
      }
    end,
    help = {
      { "Space x", "pick the module (a kit: all its modules); in the reading pane: keep or leave out a requirement" },
      { "h", "hide what SPEC.md already has" },
      { "t", "STACK.md: open its add-ons on the groups what you picked goes with (the one under the cursor when none)" },
      { "d", "DESIGN.md: the screen patterns it goes with, already checked" },
      { "A", "add what is picked (after a confirmation that brings you back here)" },
      { "★", "your SPEC.md already mentions it" },
      { "■ □ ◧ + ✓", "picked · not picked · some picked · comes with what you picked · already in SPEC.md" },
    },
    read = function(m, row)
      if row and row.kit and vim.o.columns < market.NARROW then -- no room for both: read the kit itself
        pcall(vim.api.nvim_win_set_cursor, m.wins.pane, { 1, 0 })
        market.focus(m, "pane")
      elseif row and row.kit then -- a kit: on to its first module, to read what it brings
        local first = row.kit.modules[1]
        for i, r in ipairs(m.rows) do
          if r.module and modules.key(r.module) == first then
            vim.api.nvim_win_set_cursor(m.wins.list, { i, 0 })
            return market.refresh(m)
          end
        end
      elseif row and row.module then
        pcall(vim.api.nvim_win_set_cursor, m.wins.pane, { 1, 0 })
        market.focus(m, "pane")
      end
    end,
    keys = {
      list = {
        { "<Space>", toggle, "Pick" },
        { "x", toggle, "Pick" },
        {
          "h",
          function(m)
            m.hide_done = not m.hide_done
            market.refresh(m)
          end,
          "Hide what SPEC.md has",
        },
      },
      pane = { { "<Space>", keep, "Keep or leave out" }, { "x", keep, "Keep or leave out" } },
      all = {
        { "A", add, "Add to SPEC.md" },
        { "<C-s>", add, "Add to SPEC.md" },
        { "t", to_stack, "Stack add-ons" },
        { "d", to_design, "Design patterns" },
      },
    },
  }, st)
end

M.close = market.close
M.render = market.refresh

return M
