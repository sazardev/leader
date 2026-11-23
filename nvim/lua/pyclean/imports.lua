-- ── Python import cleanup (pure, 0 tokens) ────────────────────────────────────
-- Parse, detect unused/duplicate/missing imports and rebuild the import block in
-- standard sections (future → stdlib → third-party → local). No process, no model.
-- Conservative on purpose: a name that appears ANYWHERE outside its own import
-- (even in a comment or a string) counts as used, so re-exports and `__all__` survive.
local pyimports = require "utils.pyimports"

local M = {}

local STDLIB = {
  abc = true, argparse = true, asyncio = true, base64 = true, bisect = true, builtins = true,
  calendar = true, collections = true, contextlib = true, copy = true, csv = true, dataclasses = true,
  datetime = true, decimal = true, enum = true, functools = true, gc = true, gettext = true, glob = true,
  hashlib = true, heapq = true, http = true, importlib = true, inspect = true, io = true, itertools = true,
  json = true, logging = true, math = true, multiprocessing = true, operator = true, os = true, pathlib = true,
  pickle = true, pprint = true, queue = true, random = true, re = true, shutil = true, signal = true,
  socket = true, sqlite3 = true, statistics = true, string = true, subprocess = true, sys = true,
  tempfile = true, textwrap = true, threading = true, time = true, traceback = true, types = true,
  typing = true, unittest = true, urllib = true, uuid = true, warnings = true, weakref = true, zoneinfo = true,
}

local function whole_word(line, name)
  return line:find("%f[%w_]" .. vim.pesc(name) .. "%f[^%w_]") ~= nil
end

--- Parse one import statement (already joined, possibly multiline).
---@param text string
---@return table? { module, names = {{name, as, module}}, from, future, relative }
local function parse(text)
  local flat = text:gsub("%s+", " ")
  local module, rest = flat:match "^%s*from%s+([%w_.]+)%s+import%s+(.+)$"
  local direct = flat:match "^%s*import%s+(.+)$"
  local names = {}
  if module then
    for part in (rest .. ","):gmatch "([^,]+)," do
      part = vim.trim(vim.trim(part):gsub("[%(%)]", ""))
      local name, as = part:match "^([%w_]+)%s+as%s+([%w_]+)$"
      name = name or part:match "^([%w_]+)"
      if name then
        names[#names + 1] = { name = name, as = as }
      end
    end
    return {
      module = module, names = names, from = true,
      relative = module:sub(1, 1) == ".",
      future = module == "__future__",
    }
  end
  if direct then
    for part in (direct .. ","):gmatch "([^,]+)," do
      part = vim.trim(part)
      local mod, as = part:match "^([%w_%.]+)%s+as%s+([%w_]+)$"
      mod = mod or part:match "^([%w_%.]+)"
      if mod then
        names[#names + 1] = { name = mod:match "^([%w_]+)", module = mod, as = as }
      end
    end
    if #names > 0 then
      return { module = names[1].module, names = names, from = false }
    end
  end
end

--- All import statements of a buffer, with their 1-based range and bound names.
---@param lines string[]
---@return table[]
function M.statements(lines)
  local out, i = {}, 1
  while i <= #lines do
    local trimmed = vim.trim(lines[i])
    local first, last = i, i
    local after = trimmed:match "^from%s+[%w_.]+%s+import%s*(.*)$"
    if after and after:sub(1, 1) == "(" and not after:find(")", 1, true) then
      while last < #lines and not lines[last]:find(")", 1, true) do
        last = last + 1
      end
    end
    -- keep a comment directly above an import attached to it
    while first > 1 and vim.trim(lines[first - 1]):match "^#" do
      first = first - 1
    end
    local text = table.concat(vim.list_slice(lines, first, last), "\n")
    local info = parse(text)
    if info then
      info.first, info.last, info.text = first, last, text
      info.bound = {}
      for _, name in ipairs(info.names) do
        info.bound[#info.bound + 1] = name.as or name.name
      end
      out[#out + 1] = info
    end
    i = last + 1
  end
  return out
end

local function section_of(st)
  if st.future then
    return 0
  elseif st.relative then
    return 3
  end
  return STDLIB[st.module:match "^([%w_]+)"] and 1 or 2
end

--- Statements whose bound names never appear outside an import line.
---@param lines string[]
---@return string[] removed, string[] kept_lines
function M.remove_unused(lines)
  local sts = M.statements(lines)
  if #sts == 0 then
    return {}, lines
  end
  local all = table.concat(lines, "\n")
  if all:find("__all__", 1, true) then
    return {}, lines -- re-export module: never remove anything
  end
  local drop, removed = {}, {}
  for _, st in ipairs(sts) do
    if not st.future and not st.text:find("noqa", 1, true) then
      local used = false
      for row, line in ipairs(lines) do
        local in_this = row >= st.first and row <= st.last
        if not in_this then
          local other = M.statements { line }
          if #other == 0 then -- a non-import line
            for _, name in ipairs(st.bound) do
              if whole_word(line, name) then
                used = true
                break
              end
            end
          end
        end
        if used then
          break
        end
      end
      if not used then
        for row = st.first, st.last do
          drop[row] = true
        end
        removed[#removed + 1] = vim.trim(st.text):gsub("\n", " ")
      end
    end
  end
  local out = {}
  for row, line in ipairs(lines) do
    if not drop[row] then
      out[#out + 1] = line
    end
  end
  return removed, out
end

--- Deduplicate and sort the whole import block into standard sections.
---@param lines string[]
---@return string[], integer how many duplicates were removed
function M.sort(lines)
  local sts = M.statements(lines)
  if #sts == 0 then
    return lines, 0
  end
  local first, last = sts[1].first, sts[#sts].last
  local before, after = {}, {}
  for i = 1, first - 1 do
    before[#before + 1] = lines[i]
  end
  for i = last + 1, #lines do
    after[#after + 1] = lines[i]
  end

  local groups, seen, duplicates = { {}, {}, {}, {} }, {}, 0
  for _, st in ipairs(sts) do
    local key = st.text:gsub("%s+", " ")
    if seen[key] then
      duplicates = duplicates + 1
    else
      seen[key] = true
      local g = groups[section_of(st) + 1]
      g[#g + 1] = { key = key, text = st.text }
    end
  end
  local rebuilt = {}
  for g = 1, 4 do
    if #groups[g] > 0 then
      if #rebuilt > 0 then
        rebuilt[#rebuilt + 1] = ""
      end
      table.sort(groups[g], function(a, b)
        return a.key < b.key
      end)
      for _, item in ipairs(groups[g]) do
        for _, line in ipairs(vim.split(item.text, "\n", { plain = true })) do
          rebuilt[#rebuilt + 1] = line
        end
      end
    end
  end
  return vim.list_extend(vim.list_extend(before, rebuilt), after), duplicates
end

--- Aliases used in the file that have no import yet (catalog, 0 tokens).
---@param lines string[]
---@return string[] canonical import statements
function M.missing(lines)
  local sts = M.statements(lines)
  local bound = {}
  for _, st in ipairs(sts) do
    for _, name in ipairs(st.bound) do
      bound[name] = true
    end
  end
  local missing, seen = {}, {}
  local code = {}
  for _, st in ipairs(sts) do
    code[st.first] = true
  end
  for row, line in ipairs(lines) do
    if not code[row] then
      for _, item in ipairs(pyimports.used_in_line(pyimports.mask(line))) do
        if not bound[item.label] and not seen[item.line] then
          seen[item.line] = true
          bound[item.label] = true
          missing[#missing + 1] = item.line
        end
      end
    end
  end
  return missing
end

--- Everything in one pass: remove unused, dedupe/sort, add missing.
---@param lines string[]
---@return string[], table { removed, duplicates, added }
function M.clean(lines)
  local removed, current = M.remove_unused(lines)
  local sorted, duplicates = M.sort(current)
  local added = M.missing(sorted)
  if #added > 0 then
    sorted = pyimports.apply_to_lines(sorted, added)
  end
  return sorted, { removed = removed, duplicates = duplicates, added = added }
end

return M
