-- ── SQL statements in a buffer (pure) ────────────────────────────────────────
-- Where one statement ends: a `;` that is not inside a string ('…', "…"), a dollar-quoted body ($$…$$, $fn$…$fn$, the
-- way PostgreSQL writes functions) or a comment (-- … and /* … */). Used by the runner to send the statement under the
-- cursor, and to tell a risky one (a DELETE without WHERE…) before it runs. Tested in test-langs.lua.
local M = {}

--- The statements of a text: each with its first and last line (1-based) and its text without the final `;`
---@param lines string[]
---@return { first: integer, last: integer, text: string }[]
function M.split(lines)
  local out = {}
  local buf, first = {}, nil
  local state = nil -- nil | "'" | '"' | "block" | dollar tag ("$$", "$fn$")
  local function flush(last)
    local text = vim.trim(table.concat(buf, "\n"))
    if text ~= "" and first then
      out[#out + 1] = { first = first, last = last, text = text }
    end
    buf, first = {}, nil
  end
  for row, line in ipairs(lines) do
    local i, n = 1, #line
    local piece = {}
    while i <= n do
      local c = line:sub(i, i)
      if state == nil then
        if c == "-" and line:sub(i + 1, i + 1) == "-" then -- a line comment: the rest of the line
          piece[#piece + 1] = line:sub(i)
          break
        elseif c == "/" and line:sub(i + 1, i + 1) == "*" then
          state = "block"
          piece[#piece + 1] = "/*"
          i = i + 2
        elseif c == "'" or c == '"' then
          first = first or row
          state = c
          piece[#piece + 1] = c
          i = i + 1
        elseif c == "$" then
          local tag = line:match("^%$[%w_]*%$", i)
          if tag then
            first = first or row
            state = tag
            piece[#piece + 1] = tag
            i = i + #tag
          else
            piece[#piece + 1] = c
            i = i + 1
          end
        elseif c == ";" then
          if not first and vim.trim(table.concat(piece)) ~= "" then
            first = row
          end
          buf[#buf + 1] = table.concat(piece)
          piece = {}
          flush(row)
          i = i + 1
        else
          if not first and not c:match "%s" then
            first = row
          end
          piece[#piece + 1] = c
          i = i + 1
        end
      elseif state == "block" then
        local e = line:find("*/", i, true)
        if e then
          piece[#piece + 1] = line:sub(i, e + 1)
          i, state = e + 2, nil
        else
          piece[#piece + 1] = line:sub(i)
          break
        end
      elseif state == "'" or state == '"' then
        local e = line:find(state, i, true)
        if e then
          piece[#piece + 1] = line:sub(i, e)
          i = e + 1
          if line:sub(i, i) == state then -- '' is an escaped quote: still inside
            piece[#piece + 1] = state
            i = i + 1
          else
            state = nil
          end
        else
          piece[#piece + 1] = line:sub(i)
          break
        end
      else -- a dollar-quoted body until the same tag
        local e = line:find(state, i, true)
        if e then
          piece[#piece + 1] = line:sub(i, e + #state - 1)
          i, state = e + #state, nil
        else
          piece[#piece + 1] = line:sub(i)
          break
        end
      end
    end
    local rest = table.concat(piece)
    if rest ~= "" or #buf > 0 then
      buf[#buf + 1] = rest
    end
  end
  flush(#lines)
  return out
end

--- The statement on (or right before) a line; nil when there is none
---@param lines string[]
---@param row integer 1-based
---@return { first: integer, last: integer, text: string }?
function M.at(lines, row)
  local list = M.split(lines)
  local before
  for _, s in ipairs(list) do
    if row >= s.first and row <= s.last then
      return s
    end
    if s.last < row then
      before = s
    end
  end
  return before
end

--- The text without comments, for reading what a statement does
---@param text string
---@return string
local function bare(text)
  return (text:gsub("/%*.-%*/", " "):gsub("%-%-[^\n]*", " "))
end

--- Why a statement deserves a question before it runs (nil when it does not): it changes or drops data with no limit
---@param text string
---@return string?
function M.risky(text)
  local t = " " .. bare(text):lower():gsub("%s+", " ") .. " "
  if t:match "^%s*drop " or t:find(" drop table ", 1, true) or t:find(" drop schema ", 1, true) then
    return "it drops a table or schema"
  end
  if t:match "^%s*truncate " then
    return "it empties a table"
  end
  if (t:match "^%s*delete " or t:find(" delete from ", 1, true)) and not t:find(" where ", 1, true) then
    return "a DELETE with no WHERE removes every row"
  end
  if t:match "^%s*update " and not t:find(" where ", 1, true) then
    return "an UPDATE with no WHERE changes every row"
  end
  if t:match "^%s*alter table " and t:find(" drop ", 1, true) then
    return "it drops a column or constraint"
  end
  return nil
end

--- Does a statement only read? (EXPLAIN ANALYZE runs it, so only these run without a question)
---@param text string
---@return boolean
function M.reads(text)
  local t = bare(text):lower():gsub("^%s+", "")
  if t:match "^select%s" or t:match "^values%s" or t:match "^table%s" then
    return true
  end
  if t:match "^with%s" then
    return not (t:find "%f[%w]insert%f[%W]" or t:find "%f[%w]update%f[%W]" or t:find "%f[%w]delete%f[%W]")
  end
  return false
end

return M
