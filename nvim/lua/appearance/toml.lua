-- ── Minimal TOML parser ──────────────────────────────────────────────────────
-- Covers what terminal configs use: [tables], [nested.table], dotted
-- keys, strings ("..." and '...'), arrays of strings (multiline) and inline
-- tables of strings ({ a = "x" }). Ignores [[arrays of tables]], numbers and bools.
local M = {}

--- Strips `#` comments that are not inside a string
---@param line string
---@return string
local function strip_comment(line)
  local quote
  for i = 1, #line do
    local c = line:sub(i, i)
    if quote then
      if c == quote then
        quote = nil
      end
    elseif c == '"' or c == "'" then
      quote = c
    elseif c == "#" then
      return line:sub(1, i - 1)
    end
  end
  return line
end

---@param path string "a.b.c" (quotes allowed)
---@return string[]
local function split_path(path)
  local parts = {}
  for part in path:gmatch "[^%.]+" do
    table.insert(parts, (vim.trim(part):gsub("^[\"']", ""):gsub("[\"']$", "")))
  end
  return parts
end

---@param tbl table
---@param path string[]
---@param value any
local function set_path(tbl, path, value)
  local node = tbl
  for i = 1, #path - 1 do
    node[path[i]] = type(node[path[i]]) == "table" and node[path[i]] or {}
    node = node[path[i]]
  end
  node[path[#path]] = value
end

---@param raw string
---@return any
local function parse_value(raw)
  raw = vim.trim(raw)
  local str = raw:match '^"(.*)"$' or raw:match "^'(.*)'$"
  if str then
    return str
  end
  if raw:sub(1, 1) == "[" then
    local items = {}
    for item in raw:gmatch "[\"']([^\"']*)[\"']" do
      table.insert(items, item)
    end
    return items
  end
  if raw:sub(1, 1) == "{" then
    local inline = {}
    for key, value in raw:gmatch "([%w_%-]+)%s*=%s*[\"']([^\"']*)[\"']" do
      inline[key] = value
    end
    return inline
  end
  return raw
end

---@param text string
---@return table
function M.parse(text)
  local result, section = {}, {}
  local pending_key, pending_buf

  for line in (text .. "\n"):gmatch "(.-)\r?\n" do
    line = vim.trim(strip_comment(line))

    if pending_key then
      -- multiline array/inline table: accumulate until it closes
      pending_buf = pending_buf .. " " .. line
      if line:find("]", 1, true) or line:find("}", 1, true) then
        set_path(result, pending_key, parse_value(pending_buf))
        pending_key, pending_buf = nil, nil
      end
    elseif line:match "^%[%[" then
      section = { "\0skip" } -- [[array of tables]]: its content is ignored
    elseif line:match "^%[.*%]$" then
      section = split_path(line:match "^%[(.*)%]$")
    elseif line ~= "" and section[1] ~= "\0skip" then
      local key, value = line:match "^([^=]+)=%s*(.+)$"
      if key then
        local path = vim.list_extend(vim.deepcopy(section), split_path(vim.trim(key)))
        local opener = value:sub(1, 1)
        local closed = (opener == "[" and value:find("]", 1, true)) or (opener == "{" and value:find("}", 1, true))
        if (opener == "[" or opener == "{") and not closed then
          pending_key, pending_buf = path, value
        else
          set_path(result, path, parse_value(value))
        end
      end
    end
  end
  return result
end

return M
