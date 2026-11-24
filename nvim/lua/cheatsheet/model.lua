-- ── Mappings: pure filtering and ordering ────────────────────────────────────
-- The live cheatsheet is a view over the real mappings collected by utils/cheatsheet.
-- This file has no Neovim state: search, language/mode/source filters, ordering and
-- counts can be tested without loading the editor or any plugin.
local M = {}

M.MODES = {
  { id = "n", label = "Normal", short = "N" },
  { id = "x", label = "Visual", short = "V" },
  { id = "o", label = "Operator-pending", short = "O" },
  { id = "i", label = "Insert", short = "I" },
  { id = "t", label = "Terminal", short = "T" },
}

M.SOURCES = {
  { id = "menu", label = "Leader menus" },
  { id = "global", label = "Global" },
  { id = "lsp", label = "LSP" },
  { id = "completion", label = "Completion" },
  { id = "tree", label = "File tree" },
  { id = "native", label = "Neovim" },
}

M.SORTS = {
  { id = "key", label = "Key (A→Z)", hint = "shortcut notation" },
  { id = "key_desc", label = "Key (Z→A)", hint = "reverse shortcut notation" },
  { id = "action", label = "Action (A→Z)", hint = "what the key does" },
  { id = "language", label = "Language (A→Z)", hint = "menu or Global" },
  { id = "mode", label = "Mode", hint = "Normal, Visual, Insert…" },
}

local MODE_ORDER, MODE_LABEL, MODE_SHORT, SOURCE_LABEL, SORT_LABEL = {}, {}, {}, {}, {}
for i, mode in ipairs(M.MODES) do
  MODE_ORDER[mode.id], MODE_LABEL[mode.id], MODE_SHORT[mode.id] = i, mode.label, mode.short
end
for _, source in ipairs(M.SOURCES) do
  SOURCE_LABEL[source.id] = source.label
end
for _, sort in ipairs(M.SORTS) do
  SORT_LABEL[sort.id] = sort.label
end

---@param entries table[]
---@return table
function M.state(entries)
  local modes, sources = {}, {}
  for _, mode in ipairs(M.MODES) do
    modes[mode.id] = true
  end
  for _, source in ipairs(M.SOURCES) do
    sources[source.id] = true
  end
  return { entries = entries, filter = "", language = "All", modes = modes, sources = sources, sort = "key" }
end

function M.mode_label(mode)
  return MODE_LABEL[mode] or mode
end

function M.mode_short(mode)
  return MODE_SHORT[mode] or mode:upper()
end

function M.modes_label(modes)
  local labels = {}
  for _, mode in ipairs(M.MODES) do
    if vim.tbl_contains(modes or {}, mode.id) then
      table.insert(labels, mode.label)
    end
  end
  return #labels > 0 and table.concat(labels, ", ") or "None"
end

function M.source_label(source)
  return SOURCE_LABEL[source] or source
end

function M.sort_label(sort)
  return SORT_LABEL[sort] or sort
end

--- Every word in the search must appear somewhere in the row's searchable text.
---@param entry table
---@return string
function M.haystack(entry)
  return table
    .concat({
      entry.key,
      entry.action,
      entry.full or "",
      entry.language or "",
      entry.group or "",
      M.source_label(entry.source),
      entry.scope or "",
      entry.where or "",
      entry.prefix or "",
      entry.example or "",
      entry.usage or "",
      entry.result or "",
      table.concat(entry.steps or {}, " "),
      table.concat(entry.notes or {}, " "),
      entry.note or "",
    }, " ")
    :lower()
end

local FIELD_WEIGHTS = {
  { name = "key", weight = 9 },
  { name = "action", weight = 6 },
  { name = "full", weight = 4 },
  { name = "language", weight = 6 },
  { name = "group", weight = 5 },
  { name = "source", weight = 2 },
  { name = "where", weight = 2 },
  { name = "docs", weight = 1 },
}

--- Real entries carry normalized fields so typing never rebuilds their long documentation text.
---@param entry table
---@return table
local function search_fields(entry)
  if entry.search then
    return entry.search
  end
  return {
    key = (entry.key or ""):lower(),
    action = (entry.action or ""):lower(),
    full = (entry.full or ""):lower(),
    language = (entry.language or ""):lower(),
    group = (entry.group or ""):lower(),
    source = M.source_label(entry.source):lower(),
    where = (entry.where or ""):lower(),
    docs = (entry.example or ""):lower(),
  }
end

---@param text string
---@param at integer
---@return boolean
local function boundary(text, at)
  return at == 1 or text:sub(at - 1, at - 1):match "[%w_]" == nil
end

--- Exact substrings win; otherwise match an ordered subsequence with consecutive and word-boundary bonuses.
---@param text string
---@param term string
---@return integer?, table<integer, boolean>?
local function fuzzy(text, term)
  text, term = text or "", term or ""
  if term == "" then
    return 0, {}
  end
  local first, last = text:find(term, 1, true)
  if first then
    local positions = {}
    for at = first, last do
      positions[at] = true
    end
    return 140 + (first == 1 and 45 or 0) + (boundary(text, first) and 12 or 0) - first * 0.05, positions
  end

  -- Two-letter queries stay exact; otherwise every long document would contain a g…o or a…n subsequence.
  if #term < 3 then
    return nil
  end

  local positions, cursor, previous = {}, 1, nil
  local consecutive, gaps, edges = 0, 0, 0
  for i = 1, #term do
    local at = text:find(term:sub(i, i), cursor, true)
    if not at then
      return nil
    end
    if not previous then
      edges = boundary(text, at) and 1 or 0
    elseif at == previous + 1 then
      consecutive = consecutive + 1
    else
      gaps = gaps + at - previous - 1
      if boundary(text, at) then
        edges = edges + 1
      end
    end
    positions[at] = true
    previous, cursor = at, at + 1
  end
  return 24 + consecutive * 15 + edges * 10 - gaps * 2 - previous * 0.08, positions
end

--- Fuzzy score for one mapping. Every query term must match some field.
---@param entry table
---@param query string
---@return integer?
function M.score(entry, query)
  local terms = {}
  for term in (query or ""):lower():gmatch "%S+" do
    terms[#terms + 1] = term
  end
  if #terms == 0 then
    return 0
  end
  local fields = search_fields(entry)
  local total = 0
  for _, term in ipairs(terms) do
    local best
    for _, field in ipairs(FIELD_WEIGHTS) do
      local text = fields[field.name] or ""
      local score = fuzzy(text, term)
      if score and score > 0 and not (field.name == "docs" and not text:find(term, 1, true)) then
        local weighted = score * field.weight + (field.name == "key" and 25 or 0)
        if not best or weighted > best then
          best = weighted
        end
      end
    end
    if not best then
      return nil
    end
    total = total + best
  end
  return math.floor(total)
end

--- Byte positions to paint for a query, used by the list's match highlighting.
---@param text string
---@param query string
---@return table<integer, boolean>
function M.marks(text, query)
  local out = {}
  for term in (query or ""):lower():gmatch "%S+" do
    local _, positions = fuzzy((text or ""):lower(), term)
    for at in pairs(positions or {}) do
      out[at] = true
    end
  end
  return out
end

local function filter_key(st)
  local modes = {}
  for _, mode in ipairs(M.MODES) do
    modes[#modes + 1] = st.modes[mode.id] and "1" or "0"
  end
  local sources = {}
  for _, source in ipairs(M.SOURCES) do
    sources[#sources + 1] = st.sources[source.id] and "1" or "0"
  end
  return table.concat({ st.filter or "", st.language or "All", table.concat(modes), table.concat(sources) }, "\0")
end

---@param entry table
---@param st table
---@return boolean
function M.matches(entry, st)
  if st.language ~= "All" and entry.language ~= st.language then
    return false
  end
  if not st.sources[entry.source] then
    return false
  end
  local mode = false
  for _, candidate in ipairs(entry.modes or {}) do
    mode = mode or st.modes[candidate] == true
  end
  return mode and M.score(entry, st.filter) ~= nil
end

--- Zero-padded numbers make "item 2" sort before "item 10" without a parser.
---@param text string
---@return string
local function natural(text)
  return (text:lower():gsub("%d+", function(n)
    return string.rep("0", math.max(0, 8 - #n)) .. n
  end))
end

---@param a table
---@param b table
---@param sort string
---@return boolean
function M.less(a, b, sort)
  local left, right
  if sort == "action" then
    left, right = natural(a.action), natural(b.action)
  elseif sort == "language" then
    left, right = natural(a.language or ""), natural(b.language or "")
  elseif sort == "mode" then
    left = MODE_ORDER[a.modes[1]] or 99
    right = MODE_ORDER[b.modes[1]] or 99
  else
    left, right = natural(a.key), natural(b.key)
    if sort == "key_desc" then
      return left > right
    end
  end
  if left == right then
    left, right = natural(a.key), natural(b.key)
  end
  if left == right then
    left, right = natural(a.action), natural(b.action)
  end
  return left < right
end

---@param st table
---@return table[]
function M.visible(st)
  local key = filter_key(st)
  if st._visible_key == key then
    return st._visible
  end
  local out = {}
  for _, entry in ipairs(st.entries or {}) do
    if M.matches(entry, st) then
      table.insert(out, entry)
    end
  end
  st._visible_key, st._visible = key, out
  return out
end

--- Search results are ranked globally like navi; the unfiltered browser keeps its groups and chosen order.
---@param st table
---@return table[]
function M.ranked(st)
  local list = M.visible(st)
  if vim.trim(st.filter or "") == "" then
    return list
  end
  local key = filter_key(st)
  if st._ranked_key == key then
    return st._ranked
  end
  local scored = {}
  for _, entry in ipairs(list) do
    table.insert(scored, { entry = entry, score = M.score(entry, st.filter) or 0 })
  end
  table.sort(scored, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    if (a.entry.group or ""):lower() ~= (b.entry.group or ""):lower() then
      return (a.entry.group or ""):lower() < (b.entry.group or ""):lower()
    end
    return a.entry.key < b.entry.key
  end)
  local out = vim.tbl_map(function(item)
    return item.entry
  end, scored)
  st._ranked_key, st._ranked = key, out
  return out
end

---@param st table
---@return { name: string, entries: table[] }[]
function M.grouped(st)
  local list = M.ranked(st)
  if vim.trim(st.filter or "") ~= "" then
    return #list > 0 and { { name = "Results", entries = list } } or {}
  end
  local groups = {}
  for _, entry in ipairs(list) do
    local name = entry.group or "Other"
    groups[name] = groups[name] or { name = name, entries = {} }
    table.insert(groups[name].entries, entry)
  end
  local out = vim.tbl_values(groups)
  table.sort(out, function(a, b)
    return a.name:lower() < b.name:lower()
  end)
  for _, group in ipairs(out) do
    table.sort(group.entries, function(a, b)
      return M.less(a, b, st.sort)
    end)
  end
  return out
end

---@param entries table[]
---@return { label: string, value: string, count: integer, all?: boolean }[]
function M.languages(entries)
  local counts = {}
  for _, entry in ipairs(entries) do
    counts[entry.language or "Global"] = (counts[entry.language or "Global"] or 0) + 1
  end
  local out = { { label = "All languages", value = "All", count = #entries, all = true } }
  local names = vim.tbl_keys(counts)
  table.sort(names, function(a, b)
    if (a == "Global") ~= (b == "Global") then
      return a == "Global"
    end
    return a:lower() < b:lower()
  end)
  for _, name in ipairs(names) do
    table.insert(out, { label = name, value = name, count = counts[name] })
  end
  return out
end

---@param st table
---@return string
function M.active_modes(st)
  local out = {}
  for _, mode in ipairs(M.MODES) do
    if st.modes[mode.id] then
      table.insert(out, mode.short)
    end
  end
  return #out == #M.MODES and "All" or (#out > 0 and table.concat(out, "") or "None")
end

---@param st table
---@return string
function M.active_sources(st)
  local out = {}
  for _, source in ipairs(M.SOURCES) do
    if st.sources[source.id] then
      table.insert(out, source.label)
    end
  end
  return #out == #M.SOURCES and "All" or (#out > 0 and table.concat(out, ", ") or "None")
end

return M
