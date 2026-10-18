-- ── Build with agent: a fix as edit blocks (pure) ───────────────────────────
-- A fix used to come back as the whole file: 1.4k output tokens to delete one line, and a weak model asked to "delete
-- the line X" sometimes answered with the line X alone, which then replaced the file. A fix now answers with edit blocks
-- (the exact lines it replaces, and what replaces them), applied here: cheaper, and a block that does not match the file
-- is caught before anything is written. A whole file is still accepted when most of it changes; `UNCHANGED` says the
-- file is right as it is.
local M = {}

M.FORMAT =
  [[Answer with edit blocks, one per change; each copies the exact current lines it replaces (enough of them to be unique in the file):
<<<<<<< SEARCH
<the current lines, exactly as they are>
=======
<the new lines; empty to delete them>
>>>>>>> REPLACE
When most of the file changes, answer with the whole file instead. When the file is right as it is, answer with the single word UNCHANGED. Nothing else: no prose, no fence.]]

---@class BuildEdit
---@field search string
---@field replace string

--- Does the answer use edit blocks?
---@param text string
---@return boolean
function M.has(text)
  return (text or ""):find("<<<<<<< SEARCH", 1, true) ~= nil
end

--- Is the answer "the file is right"?
---@param text string
---@return boolean
function M.unchanged(text)
  return vim.trim((text or ""):gsub("```%w*", "")) == "UNCHANGED"
end

--- The blocks of an answer; nil and why when one is not closed
---@param text string
---@return BuildEdit[]?, string?
function M.parse(text)
  local out = {}
  local lines = vim.split((text or ""):gsub("\r\n", "\n"), "\n", { plain = true })
  local i = 1
  while i <= #lines do
    if lines[i]:match "^<<<<<<< SEARCH%s*$" then
      local search, replace, mode = {}, {}, "search"
      i = i + 1
      while i <= #lines and not lines[i]:match "^>>>>>>> REPLACE%s*$" do
        if mode == "search" and lines[i]:match "^=======%s*$" then
          mode = "replace"
        elseif mode == "search" then
          search[#search + 1] = lines[i]
        else
          replace[#replace + 1] = lines[i]
        end
        i = i + 1
      end
      if i > #lines or mode ~= "replace" then
        return nil, "an edit block is not closed (SEARCH, =======, REPLACE)"
      end
      out[#out + 1] = { search = table.concat(search, "\n"), replace = table.concat(replace, "\n") }
    end
    i = i + 1
  end
  if #out == 0 then
    return nil, "no edit block"
  end
  return out
end

--- Where `search` is in `lines` (line-wise, trailing spaces ignored): the first line and how many, or nil and why
---@param lines string[]
---@param search string[]
---@return integer?, string?
local function locate(lines, search)
  local function same(a, b)
    return (a:gsub("%s+$", "")) == (b:gsub("%s+$", ""))
  end
  -- leading and trailing blank lines of a block do not have to match
  while #search > 0 and vim.trim(search[1]) == "" do
    table.remove(search, 1)
  end
  while #search > 0 and vim.trim(search[#search]) == "" do
    search[#search] = nil
  end
  if #search == 0 then
    return nil, "an edit block has an empty SEARCH"
  end
  local found
  for start = 1, #lines - #search + 1 do
    local match = true
    for k = 1, #search do
      if not same(lines[start + k - 1], search[k]) then
        match = false
        break
      end
    end
    if match then
      if found then
        return nil, ("the SEARCH starting %q matches more than one place"):format(vim.trim(search[1]):sub(1, 50))
      end
      found = start
    end
  end
  if not found then
    return nil, ("the SEARCH starting %q is not in the file"):format(vim.trim(search[1]):sub(1, 50))
  end
  return found, nil, #search
end

--- The file with the blocks applied in order; nil and why when one does not match exactly once
---@param content string
---@param text string the answer
---@return string?, string?
function M.apply(content, text)
  local blocks, why = M.parse(text)
  if not blocks then
    return nil, why
  end
  local trailing = content:sub(-1) == "\n"
  local lines = vim.split(trailing and content:sub(1, -2) or content, "\n", { plain = true })
  for _, b in ipairs(blocks) do
    local search = vim.split(b.search, "\n", { plain = true })
    local at, err, count = locate(lines, search)
    if not at then
      return nil, err
    end
    local replace = b.replace == "" and {} or vim.split(b.replace, "\n", { plain = true })
    local new = vim.list_slice(lines, 1, at - 1)
    vim.list_extend(new, replace)
    vim.list_extend(new, vim.list_slice(lines, at + count, #lines))
    lines = new
  end
  return table.concat(lines, "\n") .. (trailing and "\n" or "")
end

--- A whole-file answer much shorter than the file it replaces (a fragment taken for the file): why, else nil
---@param before string
---@param after string
---@return string?
function M.shrunk(before, after)
  local old = select(2, (before or ""):gsub("\n", ""))
  local new = select(2, (after or ""):gsub("\n", ""))
  if old >= 15 and new < old * 0.5 then
    return ("the answer has %d lines where the file has %d: it is a fragment, not the whole file"):format(new, old)
  end
end

return M
