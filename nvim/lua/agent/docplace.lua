-- ── Placing a doc comment (pure) ─────────────────────────────────────────────
-- `docs` asks the model for ONLY the doc comment, not the whole function: output tokens drop to the size of the comment
-- and the code is byte-identical by construction (it is never retyped). This joins the two: the comment goes above the
-- function replacing the one that was there (godoc, TSDoc, rustdoc, javadoc, `---`...), or inside it for the languages
-- whose docstring lives in the body (Python). It is the action's `merge` hook; the contract is in agent/actions/init.lua.
local M = {}

-- docstring languages: the comment is the first statement of the body
local INSIDE = { python = true }

local COMMENT = { "^%s*//", "^%s*#", "^%s*%-%-", "^%s*%*", "^%s*/%*", "^%s*;;" }

---@param line string
---@return boolean
local function is_comment(line)
  for _, p in ipairs(COMMENT) do
    if line:find(p) and not line:find "^%s*#%[" and not line:find "^%s*#!" then -- `#[derive]` and `#!` are code
      return true
    end
  end
  return false
end

---@param line string
---@return string
local function indent_of(line)
  return line:match "^%s*"
end

--- The block shifted so its first line sits at `indent` (the rest keeps its relative indentation)
---@param block string[]
---@param indent string
---@return string[]
local function reindent(block, indent)
  local have = indent_of(block[1])
  if have == indent then
    return block
  end
  local out = {}
  for i, l in ipairs(block) do
    if not l:match "%S" then
      out[i] = l
    elseif l:sub(1, #have) == have then
      out[i] = indent .. l:sub(#have + 1)
    else
      out[i] = indent .. vim.trim(l)
    end
  end
  return out
end

--- Drops blank lines at both ends
---@param lines string[]
---@return string[]
local function trimmed(lines)
  local first, last = 1, #lines
  while first <= last and not lines[first]:match "%S" do
    first = first + 1
  end
  while last >= first and not lines[last]:match "%S" do
    last = last - 1
  end
  return vim.list_slice(lines, first, last)
end

---@param doc string[]
---@param line string? a line of the original code that the model must not have retyped
---@return boolean
local function retyped(doc, line)
  local want = line and vim.trim(line)
  if not want or want == "" then
    return false
  end
  for _, l in ipairs(doc) do
    if vim.trim(l) == want then
      return true
    end
  end
  return false
end

--- Python: where the body starts (the line after the signature) and the existing docstring, if any
---@param lines string[]
---@return integer? sig_first, integer? sig_last, integer? doc_first, integer? doc_last
local function python_shape(lines)
  local i = 1
  while lines[i] and (not lines[i]:match "%S" or lines[i]:match "^%s*@" or is_comment(lines[i])) do
    i = i + 1
  end
  local j = i
  while lines[j] and not lines[j]:gsub("%s+#.*$", ""):match ":%s*$" do
    j = j + 1
  end
  if not lines[j] then
    return nil
  end
  local k = j + 1
  while lines[k] and not lines[k]:match "%S" do
    k = k + 1
  end
  local quote = lines[k] and (lines[k]:match [[^%s*[rRuU]?(""")]] or lines[k]:match [[^%s*[rRuU]?(''')]])
  if not quote then
    return i, j
  end
  local rest = lines[k]:gsub("^%s*[rRuU]?" .. quote, "", 1)
  local e = k
  if not rest:find(quote, 1, true) then
    e = k + 1
    while lines[e] and not lines[e]:find(quote, 1, true) do
      e = e + 1
    end
  end
  if not lines[e] then
    return i, j -- unclosed: leave it alone
  end
  return i, j, k, e
end

--- Joins the doc comment the model returned with the target's code
---@param code string[] what the model returned (the doc comment, normally)
---@param target AgentTarget
---@return string[]
function M.merge(code, target)
  local doc = trimmed(code)
  local lines = target.lines
  if #doc == 0 then
    return lines
  end

  if INSIDE[target.lang] then
    local sig_first, sig_last, doc_first, doc_last = python_shape(lines)
    if sig_first then
      if retyped(doc, lines[sig_first]) then
        return code -- the model sent the whole function anyway: it is the proposal
      end
      local body_first = doc_first or (sig_last + 1)
      local body = lines[body_first]
      local indent = body and body:match "%S" and indent_of(body) or (indent_of(lines[sig_first]) .. "    ")
      local out = vim.list_slice(lines, 1, sig_last)
      vim.list_extend(out, reindent(doc, indent))
      return vim.list_extend(out, vim.list_slice(lines, (doc_last or sig_last) + 1))
    end
    return lines
  end

  local n = 0
  while lines[n + 1] and is_comment(lines[n + 1]) do
    n = n + 1
  end
  local sig = lines[n + 1]
  if not sig then
    return lines
  end
  if retyped(doc, sig) then
    return code
  end
  local out = reindent(doc, indent_of(sig))
  return vim.list_extend(vim.list_slice(out), vim.list_slice(lines, n + 1))
end

return M
