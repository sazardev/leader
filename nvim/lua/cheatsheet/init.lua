-- ── Mappings: searchable live cheatsheet (<leader>ch / :Cheatsheet) ──────────
-- The dashboard's old NvChad list was a plain grid. This view uses Leader's own
-- full-screen market: grouped keys on the left, context on the right, and the
-- active search/language/mode/source/order always visible below.
--
--   list    j k move · { } group · Tab fold · / search · l language · f filters · s sort · r reset · y copy
--   read    j k scroll · h / Esc back
local market = require "utils.market"
local modal = require "utils.modal"
local model = require "cheatsheet.model"
local examples = require "cheatsheet.examples"

local M = {}
M.current = nil

local flat = require("ui.flat").enabled()
M.hl = flat
    and {
      title = "CheatsheetTitle",
      key = "CheatsheetKey",
      group = "CheatsheetGroup",
      action = "CheatsheetAction",
      meta = "CheatsheetMeta",
      hint = "CheatsheetHint",
      mode = "CheatsheetMode",
      example = "CheatsheetExample",
      usage = "CheatsheetUsage",
      note = "CheatsheetNote",
    }
  or {
    title = "Title",
    key = "Special",
    group = "Keyword",
    action = vim.fn.hlexists "WhichKeyDesc" > 0 and "WhichKeyDesc" or "Comment",
    meta = "Comment",
    hint = "Comment",
    mode = "Identifier",
    example = "DiagnosticOk",
    usage = vim.fn.hlexists "WhichKeyDesc" > 0 and "WhichKeyDesc" or "Comment",
    note = "Comment",
  }

---@param text string
---@param width integer
---@return string
local function fit(text, width)
  width = math.max(width, 1)
  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end
  return vim.fn.strcharpart(text, 0, math.max(width - 1, 1)) .. "…"
end

local function list_width()
  local cols = vim.o.columns
  return cols < market.NARROW and cols or math.min(44, math.floor(cols * 0.36))
end

local function cap(text)
  return (text:gsub("^%l", string.upper))
end

--- The state after a filter changes: redraw, then put the cursor on the first real key.
---@param m table
local function refresh(m)
  if not m.wins then
    return
  end
  market.refresh(m)
  for i, row in ipairs(m.rows) do
    if row.entry then
      pcall(vim.api.nvim_win_set_cursor, m.wins.list, { i, 0 })
      break
    end
  end
  market.refresh(m, true)
end

---@param st table
---@return table[]
function M.rows(st)
  local groups = model.grouped(st)
  local count = 0
  for _, group in ipairs(groups) do
    count = count + #group.entries
  end
  local rows = { { title = "MAPPINGS", count = count, total = #st.entries }, { spacer = true } }
  for _, group in ipairs(groups) do
    rows[#rows + 1] = { group = group.name, count = #group.entries }
    for _, entry in ipairs(group.entries) do
      rows[#rows + 1] = { entry = entry }
    end
    rows[#rows + 1] = { spacer = true }
  end
  return rows
end

---@param row table
---@return table[]
function M.list_line(row)
  local width = list_width()
  if row.title then
    local count = row.count == row.total and tostring(row.count) or (row.count .. " / " .. row.total)
    return {
      { "  " .. row.title, M.hl.title },
      { fit("  " .. count, math.max(width - 12, 1)), M.hl.meta },
    }
  elseif row.spacer then
    return { { "" } }
  elseif row.group then
    local name = fit(row.group:upper(), math.max(width - 10, 8))
    return {
      { "  " .. name, M.hl.group },
      { "  " .. row.count, M.hl.meta },
    }
  end
  local entry = row.entry
  local modes = {}
  for _, mode in ipairs(model.MODES) do
    if vim.tbl_contains(entry.modes, mode.id) then
      table.insert(modes, mode.short)
    end
  end
  local badge = table.concat(modes, "/")
  local prefix = " " .. badge .. " "
  local key_room = math.min(24, math.max(8, math.floor(width * 0.56)))
  local key = fit(entry.key, key_room)
  local used = vim.fn.strdisplaywidth(prefix .. key .. "  ")
  return {
    { prefix, M.hl.mode },
    { key, M.hl.key },
    { "  " .. fit(entry.action, math.max(width - used, 4)), M.hl.action },
  }
end

---@param m table
---@param row table?
---@param width integer
---@return table[], table<integer, table>
function M.pane(m, row, width)
  local lines, clickable = {}, {}
  local w = math.max(width - 4, 10)
  local function add(line, item)
    lines[#lines + 1] = line
    if item then
      clickable[#lines] = item
    end
  end
  local function paragraph(text, hl)
    for _, part in ipairs(market.wrap(text or "", w)) do
      add { { "  " .. part, hl } }
    end
  end
  local function section(label, hl)
    add { { "" } }
    add { { "  " .. label, hl } }
  end
  local function list(items, marker, hl)
    for i, text in ipairs(items or {}) do
      local lead = type(marker) == "function" and marker(i) or marker
      for j, part in ipairs(market.wrap(text, math.max(w - #lead, 8))) do
        add {
          { "  " .. (j == 1 and lead or string.rep(" ", #lead)), M.hl.meta },
          { part, hl },
        }
      end
    end
  end
  local function chips(actions)
    local line, regions, col = { { "  ", M.hl.hint } }, {}, 2
    for _, action in ipairs(actions) do
      local text = " " .. action[1] .. " "
      if col + #text + 2 > width then
        break
      end
      regions[#regions + 1] = { from = col, to = col + #text, action = action[2], value = action[3] }
      line[#line + 1] = { text, "NvModalBtn2" }
      col = col + #text
      line[#line + 1] = { "  ", M.hl.hint }
      col = col + 2
    end
    add(line, { actions = regions })
  end

  local entry = row and row.entry
  if not entry then
    add { { "  MAPPINGS", M.hl.title } }
    add { { "" } }
    paragraph("Choose a shortcut to see a concrete example and how to use it.", M.hl.meta)
    add { { "" } }
    chips { { "/ Search", "search" }, { "l Language", "language" }, { "f Filters", "filters" } }
    return lines, clickable
  end

  local described = entry.steps and entry or examples.describe(entry)
  add { { "  " .. fit(entry.group:upper(), w), M.hl.group } }
  add { { "" } }
  add { { "  " .. entry.key, M.hl.key } }
  paragraph(cap(entry.action or ""), M.hl.action)
  add { { "" } }
  add {
    { "  " .. model.modes_label(entry.modes), M.hl.mode },
    { "  ·  ", M.hl.hint },
    { entry.language, M.hl.action },
  }
  add {
    { "  " .. model.source_label(entry.source), M.hl.meta },
    { entry.prefix and ("  ·  " .. entry.prefix) or "", M.hl.meta },
  }
  local where = entry.where or "everywhere"
  add { { "  Applies to  ", M.hl.hint }, { where == "everywhere" and "Everywhere" or where, M.hl.meta } }
  add { { "" } }
  chips { { "y Copy", "copy" }, { "/ Search", "search" }, { "l Language", "language" } }

  add { { "" } }
  add { { "  EXAMPLE", M.hl.example } }
  paragraph(described.example, M.hl.usage)
  section("USAGE", M.hl.meta)
  paragraph(described.usage, M.hl.usage)
  if described.steps and #described.steps > 0 then
    section("STEPS", M.hl.meta)
    list(described.steps, function(i)
      return i .. ". "
    end, M.hl.usage)
  end
  if described.result and described.result ~= "" then
    section("RESULT", M.hl.example)
    paragraph(described.result, M.hl.usage)
  end
  if described.notes and #described.notes > 0 then
    section("NOTES", M.hl.meta)
    list(described.notes, "· ", M.hl.note)
  elseif described.note then
    section("NOTE", M.hl.meta)
    paragraph(described.note, M.hl.note)
  end
  return lines, clickable
end

---@param m table
---@return table[]
function M.summary(m)
  local shown = #model.visible(m)
  local cols = vim.o.columns
  local count = shown == #m.entries and (shown .. " shortcuts") or (shown .. " of " .. #m.entries)
  local sort_width = math.max(math.floor(cols * 0.30), 8)
  local count_width = math.max(cols - 10 - 7 - sort_width - 6, 8)
  local language = m.language == "All" and "All languages" or m.language
  local modes = model.active_modes(m)
  local sources = model.active_sources(m)
  local filters = language
    .. "  ·  "
    .. (modes == "All" and "All modes" or ("Modes " .. modes))
    .. "  ·  "
    .. (sources == "All" and "All sources" or sources)
  return {
    {
      { "  MAPPINGS", M.hl.title },
      { fit("  " .. count, count_width), M.hl.meta },
      { "   Sort ", M.hl.hint },
      { fit(model.sort_label(m.sort), sort_width), M.hl.action },
    },
    { { "  " .. fit(filters, cols - 4), M.hl.meta } },
  }
end

---@param m table
---@param mode string
---@return table[]
function M.hints(m, mode)
  local hints = {
    { "/", "Search" },
    { "l", "Language" },
    { "f", "Filters" },
    { "s", "Sort" },
    { "r", "Reset" },
    { mode == "pane" and "h" or "q", mode == "pane" and "Back" or "Close" },
  }
  if vim.o.columns >= 88 then
    table.insert(hints, #hints, { "?", "Help" })
  end
  local function width()
    return vim.fn.strdisplaywidth(table.concat(vim.tbl_map(function(segment)
      return segment[1]
    end, market.hints(hints))))
  end
  -- Keep Search, Language, Filters and Close; the rest remain in ? on very narrow terminals.
  while #hints > 4 and width() > vim.o.columns - 2 do
    table.remove(hints, #hints - 1)
  end
  return hints
end

---@param m table
---@return table
function M.spec(st)
  local function search(m)
    market.focus_input(m, "list")
  end

  local function language(m)
    local items = vim.tbl_map(function(item)
      return { label = item.label, value = item.value, desc = item.count .. " mappings" }
    end, model.languages(m.entries))
    require("tasks.picker").choose(items, {
      title = "Mappings by language",
      hint = "Enter filter · Esc cancel",
      width = 24,
      select = 1,
    }, function(item)
      if not item then
        return
      end
      m.language = item.value
      refresh(m)
    end)
  end

  local function filters(m)
    local items = {}
    for _, mode in ipairs(model.MODES) do
      items[#items + 1] = { label = mode.label, group = "Modes", checked = m.modes[mode.id] }
    end
    for _, source in ipairs(model.SOURCES) do
      items[#items + 1] = { label = source.label, group = "Sources", checked = m.sources[source.id] }
    end
    modal.checklist(items, {
      title = "Mapping filters",
      intro = { { { "  Empty groups show no mappings. r resets everything.", M.hl.hint } } },
      confirm = "Apply",
      clean = true,
    }, function(chosen)
      for _, mode in ipairs(model.MODES) do
        m.modes[mode.id] = false
      end
      for _, source in ipairs(model.SOURCES) do
        m.sources[source.id] = false
      end
      for _, index in ipairs(chosen) do
        local item = items[index]
        if item.group == "Modes" then
          for _, mode in ipairs(model.MODES) do
            if mode.label == item.label then
              m.modes[mode.id] = true
            end
          end
        else
          for _, source in ipairs(model.SOURCES) do
            if source.label == item.label then
              m.sources[source.id] = true
            end
          end
        end
      end
      refresh(m)
    end)
  end

  local function sort(m)
    local items = vim.tbl_map(function(item)
      return { label = item.label, value = item.id, desc = item.hint }
    end, model.SORTS)
    local selected = 1
    for i, item in ipairs(items) do
      if item.value == m.sort then
        selected = i
      end
    end
    require("tasks.picker").choose(
      items,
      { title = "Order mappings", hint = "Enter choose · Esc cancel", width = 22, select = selected },
      function(item)
        if not item then
          return
        end
        m.sort = item.value
        refresh(m)
      end
    )
  end

  local function reset(m)
    local fresh = model.state(m.entries)
    m.filter, m.language, m.sort = fresh.filter, fresh.language, fresh.sort
    m.modes, m.sources = fresh.modes, fresh.sources
    refresh(m)
  end

  local function copy(m, row)
    if not row or not row.entry then
      return
    end
    local ok, err = pcall(vim.fn.setreg, "+", row.entry.key)
    vim.notify(
      ok and ("Copied " .. row.entry.key) or ("Could not copy: " .. tostring(err)),
      ok and vim.log.levels.INFO or vim.log.levels.WARN
    )
  end

  local function pane_click(m, item, _, column)
    for _, region in ipairs(item.actions or {}) do
      if column - 1 >= region.from and column - 1 < region.to then
        if region.action == "copy" then
          return copy(m, market.current(m))
        elseif region.action == "search" then
          return search(m)
        elseif region.action == "language" then
          return language(m)
        elseif region.action == "filters" then
          return filters(m)
        elseif region.action == "sort" then
          return sort(m)
        elseif region.action == "reset" then
          return reset(m)
        elseif region.value then
          m.language = region.value
          return refresh(m)
        end
      end
    end
  end

  return {
    title = "Mappings",
    rows = M.rows,
    selectable = function(row)
      return row.entry ~= nil
    end,
    list_line = M.list_line,
    pane = M.pane,
    pane_click = pane_click,
    summary = M.summary,
    hints = M.hints,
    summary_rows = 3,
    live_input = {
      prefix = "/ ",
      placeholder = "Search mappings…",
      hl_prefix = M.hl.key,
      hl_placeholder = M.hl.hint,
    },
    empty = function(m)
      return "No mappings match. Change language, modes, sources or search, or press r to reset."
    end,
    help = {
      { "/", "focus the live search; type to filter immediately" },
      { "Enter", "keep the search and return to the list" },
      { "Esc", "clear the live search and return to the list" },
      { "l", "choose a language (Global includes shared shortcuts)" },
      { "f", "filter by mode and source" },
      { "s", "order by key, action, language or mode" },
      { "r", "clear search and every filter" },
      { "y", "copy the key under the cursor" },
      { "mouse", "hover to preview, click a row to read, click a chip to act" },
    },
    keys = {
      list = {
        { "/", search, "Search mappings" },
        { "l", language, "Choose language" },
        { "f", filters, "Filter mappings" },
        { "s", sort, "Order mappings" },
        { "r", reset, "Reset filters" },
        { "y", copy, "Copy key" },
      },
      all = {
        { "/", search, "Search mappings" },
        { "l", language, "Choose language" },
        { "f", filters, "Filter mappings" },
        { "s", sort, "Order mappings" },
        { "r", reset, "Reset filters" },
        { "y", copy, "Copy key" },
      },
    },
  }
end

---@param opts { entries?: table[], filter?: string, language?: string }?
---@return table?
function M.open(opts)
  opts = opts or {}
  if M.current and not M.current.closed then
    market.close(M.current)
  end
  local entries = opts.entries or require("utils.cheatsheet").entries()
  if #entries == 0 then
    vim.notify("Mappings: no keymaps were found", vim.log.levels.WARN)
    return nil
  end
  local st = model.state(entries)
  st.filter, st.language = opts.filter or "", opts.language or "All"
  local spec = M.spec(st)
  spec.on_close = function(m)
    if M.current == m then
      M.current = nil
    end
  end
  M.current = market.new(spec, st)
  return M.current
end

function M.close()
  if M.current then
    market.close(M.current)
  end
end

return M
