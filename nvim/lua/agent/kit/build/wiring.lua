-- ── Build with agent: what the plan promised and nobody calls (pure) ────────
-- Green tests can hide a feature the user never reaches: the domain implements `Expression()` and tests it, the styles
-- declare an `Expression` style, and the view calls neither, so the user never sees "12 +". The plan's `exports` are the
-- names other files were meant to rely on; one that no other (non-test) file mentions is a link missing between the
-- feature and the user. 0 tokens, any language (names are matched as words, comments out). Each finding names the file
-- that declares it (`path:line:`) so the diagnosis sees it and decides which file must call it, or that it goes.
local M = {}

--- Hooks a framework calls by itself (Bubble Tea's Init/Update/View, fmt's String, error's Error…): never "unused"
M.HOOKS = {
  main = true,
  init = true,
  Init = true,
  Update = true,
  View = true,
  String = true,
  Error = true,
  Unwrap = true,
  Is = true,
  As = true,
  ServeHTTP = true,
  Len = true,
  Less = true,
  Swap = true,
  MarshalJSON = true,
  UnmarshalJSON = true,
  MarshalText = true,
  UnmarshalText = true,
  Close = true,
  Read = true,
  Write = true,
  Format = true,
  build = true,
  render = true,
  default = true,
  constructor = true,
  toString = true,
  __init__ = true,
  __str__ = true,
  __repr__ = true,
  fmt = true,
  drop = true,
  ShortHelp = true, -- bubbles/help reads a KeyMap through its interface
  FullHelp = true,
}

local KEYWORDS = {
  ["func"] = true,
  ["type"] = true,
  ["export"] = true,
  ["default"] = true,
  ["const"] = true,
  ["let"] = true,
  ["var"] = true,
  ["function"] = true,
  ["class"] = true,
  ["interface"] = true,
  ["pub"] = true,
  ["fn"] = true,
  ["def"] = true,
  ["async"] = true,
  ["struct"] = true,
  ["enum"] = true,
  ["static"] = true,
  ["abstract"] = true,
  ["final"] = true,
  ["public"] = true,
  ["fun"] = true,
  ["val"] = true,
}

--- The name one piece of an export line promises: "Expression() string" → Expression (member: false),
--- "func (c Calculator) Expression()" and "Calculator.Expression()" → Expression (member: true: other files call it as
--- `.Expression`), "export function evaluate(…)" → evaluate; nil for prose
---@param piece string
---@return string?, boolean?, boolean? name, member, call (a function or method, not a value)
local function one(piece)
  local s = vim.trim(piece):gsub("^`", "")
  local receiver = false
  while true do
    local word = s:match "^([%a_]+)%s"
    if word and KEYWORDS[word] then
      s = vim.trim(s:sub(#word + 1))
    elseif s:match "^%b()%s*" then
      s, receiver = vim.trim((s:gsub("^%b()%s*", "", 1))), true
    else
      break
    end
  end
  local first, rest = s:match "^([%a_][%w_]*)(.*)$"
  if not first then
    return nil
  end
  local member = rest:match "^[%.:]+([%a_][%w_]*)"
  local name = member or first
  -- a sentence ("Handles the keys") is not a name: a name stands alone or is followed by code
  local after = member and rest:gsub("^[%.:]+[%a_][%w_]*", "") or rest
  if after ~= "" and not after:match "^[%s(%[<:{,=*?!]" then
    return nil
  end
  if after:match "^%s+%l+%s+%l+%s+%l+" and not after:find "[(){}%[%]*]" then
    return nil -- "Name does the thing for you": prose
  end
  if #name < 3 or M.HOOKS[name] then
    return nil
  end
  return name, (member ~= nil or receiver), after:match "^%s*[%(<]" ~= nil
end

--- The names an export line promises, each with whether it is a member (called as `.Name`). "Title, Muted, Error
--- styles" and "Colors: Fg, Muted" promise each name of the list.
---@param export string
---@return { name: string, member: boolean, call: boolean }[]
function M.names(export)
  local head = vim.trim((export or ""):gsub("%s+[—–]%s.*$", ""):gsub("%s+%-%s.*$", ""))
  local out = {}
  local list = head:gsub("^[%a%s]+:%s*", "")
  if list:find "," and not list:find "[(%[{]" then
    for piece in list:gmatch "[^,]+" do
      local name, member, call = one(piece)
      if name then
        out[#out + 1] = { name = name, member = member or false, call = call or false }
      end
    end
    return out
  end
  local name, member, call = one(head)
  if name then
    out[1] = { name = name, member = member or false, call = call or false }
  end
  return out
end

--- The first name an export line promises (nil for prose)
---@param export string
---@return string?
function M.name(export)
  local list = M.names(export)
  return list[1] and list[1].name or nil
end

---@param path string
---@return boolean
local function skip(path)
  local verify = require "agent.kit.build.verify"
  return verify.is_test(path)
    or verify.is_manifest(path)
    or path:match "%.md$" ~= nil
    or path:match "%.golden$" ~= nil
    or path:match "%.lock$" ~= nil
    or path:match "%.sum$" ~= nil
end

--- The text without comments (`//…`, `#…` at a line's start, `/* … */`, `-- …`), so a name only mentioned in a comment
--- does not count as used
---@param text string
---@return string
function M.code(text)
  text = (text or ""):gsub("/%*.-%*/", "")
  local out = {}
  for line in (text .. "\n"):gmatch "([^\n]*)\n" do
    line = line:gsub("^%s*#[^!%[].*$", ""):gsub("^%s*%-%-.*$", "")
    -- `//` outside a string: good enough for code (a URL in a string keeps its own `//` after a quote)
    local cut = line:find "%s//" or (line:find "^//" and 1)
    if cut and not line:sub(1, cut):find "[\"'`][^\"'`]*$" then
      line = line:sub(1, cut - 1)
    end
    out[#out + 1] = line
  end
  return table.concat(out, "\n")
end

--- How many times a text names it: as a word, or as a member call (`.Name`) when it is a method
---@param text string
---@param name string
---@param member boolean?
---@return integer
local function count(text, name, member)
  local escaped = name:gsub("%p", "%%%0")
  local pat = member and ("[%.:]" .. escaped .. "%f[^%w_]") or ("%f[%w_]" .. escaped .. "%f[^%w_]")
  return select(2, text:gsub(pat, ""))
end

---@param text string
---@param name string
---@param member boolean?
---@return boolean
local function mentions(text, name, member)
  return count(text, name, member) > 0
end

--- The line that declares a name in a file (1 when it is not found as a declaration)
---@param text string
---@param name string
---@return integer
local function line_of(text, name)
  local n, fallback = 0, nil
  local pat = "%f[%w_]" .. name:gsub("%p", "%%%0") .. "%f[^%w_]"
  for line in (text .. "\n"):gmatch "([^\n]*)\n" do
    n = n + 1
    if line:find(pat) then
      fallback = fallback or n
      if
        line:match "^%s*func%s"
        or line:match "^%s*type%s"
        or line:match "^%s*export%s"
        or line:match "^%s*pub%s"
        or line:match "^%s*def%s"
        or line:match "^%s*class%s"
        or line:match "^%s*fn%s"
        or line:match("^%s*" .. name:gsub("%p", "%%%0") .. "%s*=")
      then
        return n
      end
    end
  end
  return fallback or 1
end

---@class BuildUnwired
---@field path string    the file that declares it
---@field line integer
---@field name string
---@field promise string the plan's export line
---@field tests boolean  a test uses it (the feature exists, only the user cannot reach it)
---@field call boolean   a function or method (a behaviour); false for a value (a style, a color token)

--- The plan's exports that no other non-test file uses (declared in their file, so the plan did not just drift)
---@param plan BuildPlan
---@param written table<string, string> path → content
---@return BuildUnwired[]
function M.find(plan, written)
  local code, tests = {}, {}
  for path, text in pairs(written or {}) do
    if require("agent.kit.build.verify").is_test(path) then
      tests[path] = M.code(text)
    elseif not skip(path) then
      code[path] = M.code(text)
    end
  end
  local out, seen = {}, {}
  for _, f in ipairs(plan and plan.files or {}) do
    local own = code[f.path]
    if own then
      for _, export in ipairs(f.exports or {}) do
        for _, n in ipairs(M.names(export)) do
          local name, member = n.name, n.member
          local key = f.path .. ":" .. name
          -- declared here (the plan did not drift) and not used by its own file beyond the declaration
          local own_uses = member and count(own, name, true) or (count(own, name) - 1)
          if not seen[key] and mentions(own, name) and own_uses <= 0 then
            seen[key] = true
            local used = false
            for other, text in pairs(code) do
              if other ~= f.path and mentions(text, name, member) then
                used = true
                break
              end
            end
            if not used then
              local by_test = false
              for _, text in pairs(tests) do
                if mentions(text, name, member) then
                  by_test = true
                  break
                end
              end
              out[#out + 1] = {
                path = f.path,
                line = line_of(written[f.path], name),
                name = name,
                promise = export,
                tests = by_test,
                call = n.call,
              }
            end
          end
        end
      end
    end
  end
  table.sort(out, function(a, b)
    return a.path == b.path and a.line < b.line or a.path < b.path
  end)
  return out
end

--- The behaviours (functions, methods) among the findings: what fails the check. Values nobody uses (a style, a color
--- token) are context for the use phase, not a failure: dead tokens do not keep a feature from the user.
---@param list BuildUnwired[]
---@return BuildUnwired[] calls, BuildUnwired[] values
function M.split(list)
  local calls, values = {}, {}
  for _, u in ipairs(list) do
    table.insert(u.call and calls or values, u)
  end
  return calls, values
end

--- One line per finding, `path:line:` first (what verify.blame maps back to the planned file)
---@param list BuildUnwired[]
---@return string
function M.report(list)
  local out = {}
  for _, u in ipairs(list) do
    out[#out + 1] = ('%s:%d: %s is promised to other files by the plan ("%s") but no other file uses it%s: what it does never reaches the user. Call it where SPEC.md needs it (the view, the handler, the command; see the plan\'s wiring), or remove it if nothing does.'):format(
      u.path,
      u.line,
      u.name,
      u.promise,
      u.tests and " (only its tests)" or ""
    )
  end
  return table.concat(out, "\n")
end

return M
