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
  if not mode then
    return false
  end
  local text = M.haystack(entry)
  for word in (st.filter or ""):lower():gmatch "%S+" do
    if not text:find(word, 1, true) then
      return false
    end
  end
  return true
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
  return vim.tbl_filter(function(entry)
    return M.matches(entry, st)
  end, st.entries or {})
end

---@param st table
---@return { name: string, entries: table[] }[]
function M.grouped(st)
  local groups = {}
  for _, entry in ipairs(M.visible(st)) do
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
