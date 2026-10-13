-- ── Conventional Commits: pure analysis (no UI, no git) ──────────────────────
-- The only thing that decides whether a message is valid and which type/scope to suggest. Types and limits live in
-- settings.git.commit; the .githooks/commit-msg hook validates the same on any `git commit`.
local M = {}

local function cfg()
  return require("core.settings").git.commit
end

-- directories that say nothing as a scope
local GENERIC = {
  nvim = true,
  lua = true,
  src = true,
  lib = true,
  app = true,
  pkg = true,
  internal = true,
  cmd = true,
  plugins = true,
  utils = true,
  core = true,
}

---@class CommitHeader
---@field type string
---@field scope string?
---@field breaking boolean
---@field subject string

--- Splits `type(scope)!: subject` WITHOUT validating the type; nil if it does not have that shape
---@param line string
---@return CommitHeader?
function M.split(line)
  local type_, scope, bang, sep, subject = line:match "^(%l+)%(([^()]*)%)(!?):( ?)(.*)$"
  if not type_ then
    type_, bang, sep, subject = line:match "^(%l+)(!?):( ?)(.*)$"
  end
  if not type_ or (subject ~= "" and sep == "") then
    return nil
  end
  return {
    type = type_,
    scope = (scope ~= nil and scope ~= "") and scope or nil,
    breaking = bang == "!",
    subject = subject,
  }
end

---@param type_ string
---@return boolean
function M.known_type(type_)
  for _, t in ipairs(cfg().types) do
    if t[1] == type_ then
      return true
    end
  end
  return false
end

--- Validates the first line: `type(scope)!: subject`, type from the list, max length
---@param line string
---@return CommitHeader?, string? err
function M.parse_header(line)
  local h = M.split(line)
  if not h or h.subject == "" then
    return nil, "the first line must look like `type(scope): subject`"
  end
  if not M.known_type(h.type) then
    return nil, ("unknown type `%s`"):format(h.type)
  end
  if #line > cfg().subject_max then
    return nil, ("the first line has %d characters (max %d)"):format(#line, cfg().subject_max)
  end
  return h
end

---@class CommitCheck
---@field state "empty"|"ok"|"error"|"incomplete"
---@field header CommitHeader?
---@field err string?
---@field len integer
---@field max integer

--- State of the first line for the live indicator. `incomplete` = fine so far but there is no subject yet
---@param line string
---@return CommitCheck
function M.check(line)
  local max = cfg().subject_max
  local len = vim.fn.strchars(line)
  if vim.trim(line) == "" then
    return { state = "empty", len = 0, max = max }
  end
  local h = M.split(line)
  if h and M.known_type(h.type) and h.subject == "" then
    return { state = "incomplete", header = h, len = len, max = max }
  end
  local parsed, err = M.parse_header(line)
  if not parsed then
    return { state = "error", err = err, header = h, len = len, max = max }
  end
  return { state = "ok", header = parsed, len = len, max = max }
end

--- Changes the type (or scope) of the first line keeping the rest; with an empty line it creates the template
---@param line string
---@param patch { type: string?, scope: string|false? }  scope = false removes the scope
---@return string
function M.rewrite(line, patch)
  local h = M.split(line) or { type = "", subject = vim.trim(line), breaking = false }
  local type_ = patch.type or h.type
  local scope = h.scope
  if patch.scope == false then
    scope = nil
  elseif patch.scope then
    scope = patch.scope
  end
  return ("%s%s%s: %s"):format(type_, scope and ("(" .. scope .. ")") or "", h.breaking and "!" or "", h.subject)
end

--- Likely type based on what is being committed (nil = no hint)
---@param files string[]
---@return string?
function M.suggest_type(files)
  if #files == 0 then
    return nil
  end
  local function all(pred)
    for _, f in ipairs(files) do
      if not pred(f) then
        return false
      end
    end
    return true
  end
  if all(function(f)
    return f:match "^docs/" or f:match "%.md$" or f:match "%.txt$"
  end) then
    return "docs"
  end
  if
    all(function(f)
      return f:match "^tests?/" or f:match "_test%." or f:match "%.test%." or f:match "%.spec%."
    end)
  then
    return "test"
  end
  if all(function(f)
    return f:match "^%.github/" or f:match "Jenkinsfile" or f:match "%.gitlab%-ci"
  end) then
    return "ci"
  end
  if
    all(function(f)
      return f:match "lock" or f:match "go%.sum$" or f:match "go%.mod$" or f:match "package%.json$"
    end)
  then
    return "chore"
  end
  return nil
end

--- Suggested scopes: first those that come from the paths AND are already in the history, then those
--- from the paths, then the most used ones in the history
---@param files string[]
---@param history string[]
---@return string[]
function M.suggest_scopes(files, history)
  local counts = {}
  local function add(scope)
    scope = (scope or ""):gsub("^%.", ""):lower()
    if scope ~= "" and not GENERIC[scope] then
      counts[scope] = (counts[scope] or 0) + 1
    end
  end
  for _, f in ipairs(files) do
    local parts = vim.split(f, "/", { plain = true })
    local name = table.remove(parts):gsub("%..*$", "")
    for _, dir in ipairs(parts) do
      if not GENERIC[dir] then
        add(dir)
        break
      end
    end
    add(name)
  end

  local rank = {}
  for i, scope in ipairs(history) do
    rank[scope] = i
  end
  local from_paths = vim.tbl_keys(counts)
  table.sort(from_paths, function(a, b)
    if (rank[a] ~= nil) ~= (rank[b] ~= nil) then
      return rank[a] ~= nil
    end
    if counts[a] ~= counts[b] then
      return counts[a] > counts[b]
    end
    return (rank[a] or 0) < (rank[b] or 0) or a < b
  end)

  local result, seen = {}, {}
  for _, scope in ipairs(vim.list_extend(from_paths, vim.list_slice(history, 1, 8))) do
    if not seen[scope] and #result < 12 then
      seen[scope] = true
      result[#result + 1] = scope
    end
  end
  return result
end

--- Scopes used by the history (subject lines), most to least frequent
---@param subjects string
---@return string[]
function M.history_scopes(subjects)
  local counts = {}
  for line in subjects:gmatch "[^\n]+" do
    local scope = line:match "^%l+%(([^()]+)%)!?:"
    if scope then
      counts[scope] = (counts[scope] or 0) + 1
    end
  end
  local list = vim.tbl_keys(counts)
  table.sort(list, function(a, b)
    return counts[a] ~= counts[b] and counts[a] > counts[b] or a < b
  end)
  return list
end

--- Strips code fences and quotes that some models add around the message
---@param out string
---@return string[]
function M.clean_message(out)
  local lines = vim.tbl_filter(function(l)
    return not l:match "^%s*```"
  end, vim.split(out, "\n", { plain = true }))
  local msg = vim.trim(table.concat(lines, "\n")):gsub("^[\"'`]+", ""):gsub("[\"'`]+$", "")
  return vim.split(msg, "\n", { plain = true })
end

return M
