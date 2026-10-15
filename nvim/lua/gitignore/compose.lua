-- ── Writing the rules ────────────────────────────────────────────────────────
-- Pure. `rules` is what a .gitignore already says; `build` turns the chosen presets into text that adds only what is missing
-- (a rule is never written twice, not even across presets: `dist/` is in Node, Python and Go but lands once). Whole blocks
-- that have nothing new disappear with their comment, and a preset with nothing new is skipped.
local M = {}

---@param line string
---@return string?  the rule, or nil for blanks and comments
local function rule(line)
  local s = line:gsub("%s+$", "")
  if s == "" or s:sub(1, 1) == "#" then
    return nil
  end
  return s
end

--- The set of rules a text already has
---@param text string?
---@return table<string, true>
function M.rules(text)
  local seen = {}
  for _, line in ipairs(vim.split((text or ""):gsub("\r\n", "\n"), "\n", { plain = true })) do
    local r = rule(line)
    if r then
      seen[r] = true
    end
  end
  return seen
end

--- How many rules of a preset a .gitignore does not have yet
---@param preset IgnorePreset
---@param seen table<string, true>
---@return integer
function M.missing(preset, seen)
  local n = 0
  for _, line in ipairs(preset.body) do
    local r = rule(line)
    if r and not seen[r] then
      n = n + 1
    end
  end
  return n
end

--- A preset as lines: its header, then its blocks without what `seen` has (updated as rules are taken)
---@param preset IgnorePreset
---@param seen table<string, true>
---@return string[]? lines, integer added
local function section(preset, seen)
  local blocks, current = {}, {}
  for _, line in ipairs(preset.body) do
    if line == "" then
      if #current > 0 then
        blocks[#blocks + 1] = current
        current = {}
      end
    else
      current[#current + 1] = line
    end
  end
  if #current > 0 then
    blocks[#blocks + 1] = current
  end

  local out, added = { preset.header }, 0
  for _, block in ipairs(blocks) do
    local kept, fresh = {}, 0
    for _, line in ipairs(block) do
      local r = rule(line)
      if not r then
        kept[#kept + 1] = line
      elseif not seen[r] then
        seen[r] = true
        kept[#kept + 1] = line
        fresh = fresh + 1
      end
    end
    if fresh > 0 then
      if #out > 1 then
        out[#out + 1] = ""
      end
      vim.list_extend(out, kept)
      added = added + fresh
    end
  end
  if added == 0 then
    return nil, 0
  end
  return out, added
end

--- The text to write (a new file) or to append (`existing` given), and how many rules it adds
---@param presets IgnorePreset[] in the order they are written
---@param existing string? the current .gitignore
---@return string text, integer added
function M.build(presets, existing)
  local seen = M.rules(existing)
  local parts, total = {}, 0
  for _, preset in ipairs(presets) do
    local lines, added = section(preset, seen)
    if lines then
      parts[#parts + 1] = table.concat(lines, "\n")
      total = total + added
    end
  end
  if total == 0 then
    return "", 0
  end
  local text = table.concat(parts, "\n\n") .. "\n"
  if existing and existing:match "%S" then
    text = (existing:match "\n$" and "\n" or "\n\n") .. text
  end
  return text, total
end

return M
