-- ── Build with agent: a model's answer as a clean file (pure) ───────────────
-- Asked for "only the file", models still wrap it: a ``` fence with a sentence around it, the prompt's own `<file path>`
-- tags echoed back, tool-call markup leaking from the CLI (`</｜｜DSML｜｜ parameter>`), "I'll make the file…" before the
-- code. Each of those cost a full fix round (a check fails on a stray line, a diagnosis, a rewrite). Here they go before
-- the file is written; what is still not a file is reported (`problem`) so the request is asked again once.
local M = {}

--- Lines that are markup, never content: the prompt's file tags and the tool-call wrappers some backends leak
local MARKUP = {
  "^%s*</?file[%s>]",
  "^%s*</?file%s+path=",
  "｜DSML｜",
  "<|[%w_]+|>",
  "^%s*</?parameter[%s>]",
  "^%s*</?invoke[%s>]",
  "^%s*</?function_calls>",
  "^%s*</?tool_call>",
  "^%s*</?answer>",
}

--- The first line a file of this kind can start with (anything before it is chatter)
local STARTS = {
  go = { "^package%s", "^//", "^/%*" },
  mod = { "^module%s", "^//" },
  json = { "^%s*[%[{]" },
  rs = {
    "^use%s",
    "^mod%s",
    "^pub[%s(]",
    "^fn%s",
    "^//",
    "^#!?%[",
    "^const%s",
    "^static%s",
    "^struct%s",
    "^enum%s",
    "^impl",
    "^type%s",
    "^/%*",
  },
  toml = { "^%[", "^#", "^[%w_%-]+%s*=" },
  html = { "^%s*<!", "^%s*<html", "^%s*<!%-%-" },
  yaml = { "^%-%-%-", "^#", "^[%w_%-\"']+%s*:" },
  yml = { "^%-%-%-", "^#", "^[%w_%-\"']+%s*:" },
}

--- What a sentence to the reader looks like (an answer that talks instead of being the file)
local CHATTER = {
  "^Here",
  "^Sure",
  "^Certainly",
  "^Okay",
  "^OK[,.]",
  "^I'll",
  "^I will",
  "^I'm",
  "^I am",
  "^I've",
  "^Let me",
  "^Below",
  "^Now",
  "^This file",
  "^The file",
  "^The corrected",
  "^The fixed",
  "^The updated",
  "^Note:",
  "^Notes:",
  "^Explanation",
  "^Changes",
  "^Summary:",
  "^Returning",
  "^Done",
}

---@param line string
---@return boolean
local function markup(line)
  for _, pat in ipairs(MARKUP) do
    if line:find(pat) then
      return true
    end
  end
  return false
end

---@param line string
---@return boolean
function M.chatter(line)
  if line:find "[{}();=<>]" then -- code (`Now = time.Now()`, `Done()`), not a sentence
    return false
  end
  for _, pat in ipairs(CHATTER) do
    if line:find(pat) then
      return true
    end
  end
  return false
end

---@param path string?
---@return string
local function ext(path)
  return ((path or ""):match "%.([%w]+)$" or ""):lower()
end

--- The fenced blocks of a text: { lang, body, from, to } in order
---@param lines string[]
---@return { body: string[], from: integer, to: integer }[]
local function fences(lines)
  local out, open = {}, nil
  for i, l in ipairs(lines) do
    if l:match "^```" then
      if open then
        out[#out + 1] = { body = vim.list_slice(lines, open + 1, i - 1), from = open, to = i }
        open = nil
      else
        open = i
      end
    end
  end
  return out
end

--- The answer as file content: markup lines out; the fenced block when the answer is a fence with prose around it (a
--- Markdown file keeps its own fences: only a fence around the whole answer goes); chatter before the first line the
--- file can start with, and after the code, out
---@param text string
---@param path string?
---@return string
function M.file(text, path)
  local lines = vim.split((text or ""):gsub("\r\n", "\n"), "\n", { plain = true })
  lines = vim.tbl_filter(function(l)
    return not markup(l)
  end, lines)
  local kind = ext(path)
  local blocks = fences(lines)
  if kind == "md" or kind == "markdown" then
    -- only a fence around the whole answer is not the file's own
    local first, last = 1, #lines
    while first <= last and vim.trim(lines[first]) == "" do
      first = first + 1
    end
    while last >= first and vim.trim(lines[last]) == "" do
      last = last - 1
    end
    if lines[first] and lines[first]:match "^```" and lines[last] and lines[last]:match "^```%s*$" and first < last then
      lines = vim.list_slice(lines, first + 1, last - 1)
    end
  elseif #blocks > 0 then
    local outside = false
    for i, l in ipairs(lines) do
      local inside = false
      for _, b in ipairs(blocks) do
        if i >= b.from and i <= b.to then
          inside = true
        end
      end
      if not inside and vim.trim(l) ~= "" then
        outside = true
        break
      end
    end
    if outside or #blocks == 1 then
      -- the largest block is the file (a model that explains, then shows it, or shows it twice)
      local best = blocks[1]
      for _, b in ipairs(blocks) do
        if #b.body > #best.body then
          best = b
        end
      end
      lines = best.body
    end
  end
  -- chatter before the first line this kind of file can start with
  local starts = STARTS[kind]
  local first = 1
  while lines[first] and (vim.trim(lines[first]) == "" or M.chatter(lines[first])) do
    first = first + 1
  end
  if starts then
    for i = first, #lines do
      local fits = false
      for _, pat in ipairs(starts) do
        if lines[i]:find(pat) then
          fits = true
          break
        end
      end
      if fits then
        first = i
        break
      end
    end
  end
  lines = vim.list_slice(lines, first, #lines)
  -- chatter after the code: a trailing sentence to the reader
  local last = #lines
  while last > 0 and (vim.trim(lines[last]) == "" or M.chatter(lines[last])) do
    last = last - 1
  end
  lines = vim.list_slice(lines, 1, last)
  return table.concat(lines, "\n"):gsub("%s+$", "") .. "\n"
end

--- The JSON object a model answered, decoded (nil when there is none): from the first `{` to the last `}` (prose or a
--- fence around it does not matter), else the first balanced `{…}`. Lua's `%b{}` alone is not enough: it does not know
--- strings, so a `}` inside a text value ("expect": "the set {1, 2}") cuts the object short.
---@param text string
---@param opts table? vim.json.decode options
---@return table?
function M.json(text, opts)
  text = text or ""
  opts = opts or {} -- vim.json.decode rejects an explicit nil
  local first, last = text:find("{", 1, true), nil
  for i = #text, 1, -1 do
    if text:sub(i, i) == "}" then
      last = i
      break
    end
  end
  if first and last and last > first then
    local ok, data = pcall(vim.json.decode, text:sub(first, last), opts)
    if ok and type(data) == "table" then
      return data
    end
  end
  local ok, data = pcall(vim.json.decode, text:match "%b{}" or "", opts)
  return ok and type(data) == "table" and data or nil
end

--- Why this content is still not a file of its kind (nil when it is): markup left, a fence, prose where code starts
---@param content string
---@param path string?
---@return string?
function M.problem(content, path)
  content = content or ""
  if vim.trim(content) == "" then
    return "the answer was empty"
  end
  for line in content:gmatch "[^\n]+" do
    if markup(line) then
      return ("it contains markup that is not code (%q)"):format(vim.trim(line):sub(1, 60))
    end
  end
  local kind = ext(path)
  if kind ~= "md" and kind ~= "markdown" then -- an edit block taken for the file: its markers would break the build
    for line in content:gmatch "[^\n]+" do
      if line:match "^<<<<<<< " or line:match "^>>>>>>> " or line:match "^=======%s*$" then
        return ("it contains edit block markers (%q)"):format(vim.trim(line))
      end
    end
  end
  local head = content:match "^%s*([^\n]*)" or ""
  if kind ~= "md" and kind ~= "markdown" and head:match "^```" then
    return "it is wrapped in a ``` fence"
  end
  if M.chatter(head) then
    return ("it starts with a sentence, not code (%q)"):format(head:sub(1, 60))
  end
  if kind == "go" and not (content:find "^%s*package%s" or content:find "\npackage%s") then
    return "a Go file without a `package` clause"
  end
  if kind == "json" then
    local ok = pcall(vim.json.decode, content)
    if not ok then
      return "it is not valid JSON"
    end
  end
  return nil
end

return M
