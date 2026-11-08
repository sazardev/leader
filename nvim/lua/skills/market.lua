-- ── Skills: full-screen marketplace (<leader>aK) ─────────────────────────────
-- The whole screen: skills by group on the left (installed, suggested by your
-- model, catalog), the one under the cursor on the right (what it is + its
-- instructions), and under both what it will do. Nothing leaves the view:
-- edit/delete/install all return here (Esc/h goes back, q closes), so you
-- never repeat the command. Same widget as the SPEC.md modules (utils/market).
--   list    j k move · Space install/toggle · e edit · n new · d delete · A apply suggestions · / filter
--   read    j k scroll · Esc back (changes stay, the market stays open)
local market = require "utils.market"
local modal = require "utils.modal"

local M = {}

---@param st table marketplace state
---@return table<string, boolean> installed ids
local function installed_ids(st)
  local out = {}
  for _, s in ipairs(st.skills) do
    out[s.id] = true
  end
  return out
end

--- The list: installed, suggested, catalog (narrowed by the filter)
---@param st table
---@return table[]
function M.rows(st)
  local needle = vim.trim(st.filter or ""):lower()
  local rows = { { title = "SKILLS" }, { spacer = true } }
  local function hits(text)
    return needle == "" or text:lower():find(needle, 1, true) ~= nil
  end
  local suggested = {}
  for _, s in ipairs(st.suggestions or {}) do
    suggested[s.id] = s
  end
  local function section(id, items, make_row)
    items = vim.tbl_filter(function(e)
      return hits(e.id .. " " .. (e.description or e.desc or "") .. " " .. (e.name or ""))
    end, items)
    if #items == 0 then
      return
    end
    rows[#rows + 1] = { group = id }
    for _, e in ipairs(items) do
      rows[#rows + 1] = make_row(e)
    end
    rows[#rows + 1] = { spacer = true }
  end
  section("Installed", st.skills, function(s)
    return { id = s.id, skill = s, state = s.autoinvoke and "on" or "off" }
  end)
  local suggested_list = vim.tbl_filter(function(s)
    return not installed_ids(st)[s.id]
  end, vim.tbl_values(suggested))
  table.sort(suggested_list, function(a, b)
    return a.id < b.id
  end)
  section("Suggested for " .. (st.class or "medium") .. " model", suggested_list, function(s)
    return { id = s.id, suggestion = s, state = "suggested" }
  end)
  local catalog = vim.tbl_filter(function(e)
    return not installed_ids(st)[e.id]
  end, st.catalog or {})
  section("Catalog", catalog, function(e)
    return { id = e.id, entry = e, state = "catalog" }
  end)
  return rows
end

local MARK = { on = "■", off = "□", suggested = "+", catalog = "○" }

---@param row table
---@return MarketLine
function M.list_line(row)
  if row.title then
    return { { "  " .. row.title, modal.hl.key } }
  elseif row.spacer then
    return { { "" } }
  elseif row.group then
    return { { (row.collapsed and "▸ " or "  ") .. row.group:upper(), modal.hl.muted } }
  end
  local name = row.skill and row.skill.name or (row.entry and row.entry.name) or (row.suggestion and row.suggestion.id) or "?"
  local lit = row.state == "on" or row.state == "suggested"
  return {
    { " " .. (MARK[row.state] or "○") .. " ", lit and modal.hl.mark or modal.hl.muted },
    { name, lit and modal.hl.file or modal.hl.muted },
    { row.suggestion and ("  · " .. row.suggestion.why):sub(1, 30) or "", modal.hl.muted },
  }
end

---@param skill table? installed skill
---@param entry table? catalog entry
---@param suggestion table? suggestion
---@param width integer
---@return MarketLine[]
local function detail(skill, entry, suggestion, width)
  local w = width - 4
  local lines = {}
  local name = skill and skill.name or (entry and entry.name) or (suggestion and suggestion.id)
  local id = skill and skill.id or (entry and entry.id) or (suggestion and suggestion.id)
  lines[#lines + 1] = { { "  " .. name:upper(), modal.hl.key } }
  local desc = (skill and skill.description) or (entry and entry.desc) or (suggestion and suggestion.why) or ""
  for _, row in ipairs(market.wrap(desc, w)) do
    lines[#lines + 1] = { { "  " .. row, modal.hl.muted } }
  end
  local facts = {}
  if skill then
    facts[#facts + 1] = skill.autoinvoke and "ON: the model sees it" or "OFF: dormant (Space to wake)"
    facts[#facts + 1] = skill.path and vim.fn.fnamemodify(skill.path, ":~:.") or ""
    if not skill.valid then
      facts[#facts + 1] = "⚠ " .. table.concat(skill.errors or {}, "; ")
    end
  elseif suggestion then
    facts[#facts + 1] = suggestion.why
    facts[#facts + 1] = "Space installs it (writes .agents/skills)"
  elseif entry then
    facts[#facts + 1] = "source: " .. (entry.repo or entry.source or "skills.sh")
  end
  if #facts > 0 then
    lines[#lines + 1] = { { "" } }
    for _, f in ipairs(facts) do
      if f ~= "" then
        lines[#lines + 1] = { { "  " .. f, modal.hl.muted } }
      end
    end
  end
  local body = skill and skill.body or (entry and entry.desc) or ""
  if body and body ~= "" then
    lines[#lines + 1] = { { "" } }
    lines[#lines + 1] = { { "  INSTRUCTIONS", modal.hl.muted } }
    for _, para in ipairs(vim.split(body, "\n", { plain = true })) do
      if vim.trim(para) == "" then
        lines[#lines + 1] = { { "" } }
      else
        for _, row in ipairs(market.wrap(vim.trim(para), w)) do
          lines[#lines + 1] = { { "  " .. row, modal.hl.file } }
        end
      end
    end
  end
  lines[#lines + 1] = { { "" } }
  lines[#lines + 1] = { { "  e edit · Space install/toggle · d delete (installed) · Esc back", modal.hl.muted } }
  return lines
end

---@param st table
---@return MarketLine[]
local function summary(st)
  local on, off = 0, 0
  for _, s in ipairs(st.skills or {}) do
    if s.autoinvoke then
      on = on + 1
    else
      off = off + 1
    end
  end
  local lines = { { { ("  %d ON · %d OFF · model %s"):format(on, off, st.class or "medium"), modal.hl.key } } }
  if st.detected and #st.detected > 0 then
    lines[#lines + 1] = { { ("  Detected: %s"):format(table.concat(st.detected, " · ")):sub(1, vim.o.columns - 6), modal.hl.muted } }
  end
  local pending = 0
  for _, s in ipairs(st.suggestions or {}) do
    if s.action == "install" or s.action == "enable" then
      pending = pending + 1
    end
  end
  lines[#lines + 1] = {
    {
      pending > 0 and ("  %d suggested for your model: A installs them (0-config, no question)"):format(pending)
        or "  Nothing to suggest: your model and stack are covered",
      modal.hl.muted,
    },
  }
  lines[#lines + 1] = { { "  Space install/toggle · e edit · n new · d delete · / search catalog · Esc back", modal.hl.muted } }
  return lines
end

--- Opens the marketplace. The state lives on the market table so tests can drive it.
---@param opts { on_close?: fun()? }?
---@return table?
function M.open(opts)
  opts = opts or {}
  local store = require "skills.store"
  local facts_ok, facts = pcall(function()
    return require("skills").facts()
  end)
  local st = {
    skills = store.list(),
    suggestions = require("skills").suggest(),
    catalog = store.CURATED,
    class = require("skills").class(),
    detected = facts_ok and facts and facts.hints or {},
  }
  -- keep the summary tall enough for the detected line
  local function refresh_all(m)
    st.skills = store.list()
    st.suggestions = require("skills").suggest()
    st.class = require("skills").class()
    local ok, f = pcall(function()
      return require("skills").facts()
    end)
    st.detected = ok and f and f.hints or {}
    market.refresh(m)
  end
  local function find_skill(id)
    for _, s in ipairs(st.skills) do
      if s.id == id then
        return s
      end
    end
  end
  local function toggle(m, row)
    if not row or not row.id then
      return
    end
    if row.skill then
      store.set_enabled(row.skill, not row.skill.autoinvoke)
      refresh_all(m)
    elseif row.entry or row.suggestion then
      local entry = row.entry or (function()
        for _, e in ipairs(store.CURATED) do
          if e.id == row.id then
            return e
          end
        end
      end)()
      if not entry then
        require("utils.log").warn("Skills: no catalog source for " .. row.id)
        return
      end
      require("skills.catalog").install(entry, nil, function(ok, msg)
        if ok then
          require("utils.log").info("Skills: " .. (msg or row.id))
        else
          require("utils.log").warn("Skills: " .. (msg or "install failed"))
        end
        refresh_all(m)
      end)
    end
  end
  local function edit_row(m, row)
    local skill = row.skill or (row.id and find_skill(row.id))
    if not skill then
      return require("utils.log").warn "Skills: install it first (Space) to edit it"
    end
    -- edit in a split over the marketplace; coming back the market is still there
    vim.cmd.edit(vim.fn.fnameescape(skill.path))
    vim.schedule(function()
      refresh_all(m)
    end)
  end
  local function delete_row(m, row)
    local skill = row.skill or (row.id and find_skill(row.id))
    if not skill then
      return
    end
    modal.confirm({ { { ("Delete skill «" .. skill.id .. "»?"), modal.hl.key } }, { { "It goes to Leader's trash (30 days), not gone forever.", modal.hl.muted } } }, {
      title = "Delete skill",
      confirm = "Delete",
      danger = true,
    }, function()
      local ok, err = store.remove(skill)
      if ok then
        require("utils.log").info("Skills: " .. skill.id .. " trashed")
      else
        require("utils.log").warn("Skills: " .. (err or "failed"))
      end
      refresh_all(m)
    end)
  end
  local function new_skill(m)
    require("skills").create()
    vim.schedule(function()
      refresh_all(m)
    end)
  end
  local function apply_all(m)
    require("skills").apply_suggestions()
    vim.schedule(function()
      refresh_all(m)
    end)
  end
  local function search_catalog(m)
    vim.ui.input({ prompt = "Search skills: " }, function(text)
      if text == nil then
        return
      end
      require("skills.catalog").search(vim.trim(text), function(entries)
        st.catalog = entries
        market.refresh(m)
      end)
    end)
  end

  return market.new({
    title = "Skills",
    summary_rows = 6,
    rows = M.rows,
    selectable = function(row)
      return row.skill ~= nil or row.entry ~= nil or row.suggestion ~= nil
    end,
    list_line = M.list_line,
    pane = function(m, row, width)
      if not row or (not row.skill and not row.entry and not row.suggestion) then
        return { { { "  Pick a skill (j/k), Space installs it", modal.hl.muted } } }, {}
      end
      return detail(row.skill, row.entry, row.suggestion, width), {}
    end,
    summary = summary,
    hints = function(m, mode)
      if mode == "pane" then
        return { { "Esc", "back" }, { "Space", "install/toggle" }, { "e", "edit" }, { "d", "delete" }, { "?", "keys" } }
      end
      return {
        { "Space", "install/toggle" },
        { "e", "edit" },
        { "n", "new" },
        { "d", "delete" },
        { "A", "apply suggestions" },
        { "/", "search" },
        { "?", "keys" },
      }
    end,
    help = {
      { "Space", "Space on installed toggles on/off; on suggested/catalog installs it (.agents/skills)" },
      { "e", "edit the SKILL.md (the market stays open underneath)" },
      { "n", "new skill: id, trigger line, instructions" },
      { "d", "delete to Leader's trash (30 days)" },
      { "A", "apply every suggestion for your model (0-config, no question)" },
      { "/", "search the catalog (skills.sh + offline list)" },
      { "★", "suggested because your model/stack asked for it" },
    },
    read = function(m, row)
      pcall(vim.api.nvim_win_set_cursor, m.wins.pane, { 1, 0 })
      market.focus(m, "pane")
    end,
    keys = {
      list = {
        { "<Space>", toggle, "Install/toggle" },
        { "x", toggle, "Install/toggle" },
        { "e", edit_row, "Edit" },
        { "n", new_skill, "New skill" },
        { "d", delete_row, "Delete" },
        { "A", apply_all, "Apply suggestions" },
        { "/", search_catalog, "Search catalog" },
      },
      pane = {
        { "<Space>", toggle, "Install/toggle" },
        { "e", edit_row, "Edit" },
        { "d", delete_row, "Delete" },
      },
      all = {
        { "A", apply_all, "Apply suggestions" },
      },
    },
    on_close = opts.on_close,
  }, st)
end

M.close = market.close

return M
