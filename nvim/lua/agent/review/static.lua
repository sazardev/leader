-- ── What can be checked in a staged diff without a model ─────────────────────
-- Secrets, conflict markers, debugger leftovers and sensitive files, found by patterns in the ADDED lines. It runs before
-- anything is sent, costs nothing, and its findings are as real as the model's (they land as diagnostics too).
local diff = require "agent.review.diff"

local M = {}

local SEV = vim.diagnostic.severity
M.SOURCE = "staged review"

--- Lua patterns have no `{n}`: a class repeated n times
---@param class string
---@param n integer
---@return string
local function rep(class, n)
  return class:rep(n)
end

---@type { [1]: string, [2]: string, [3]: string }[] name, pattern, message
local SECRETS = {
  { "aws", "AKIA" .. rep("[0-9A-Z]", 16), "looks like an AWS access key" },
  { "private key", "%-%-%-%-%-BEGIN [%u ]*PRIVATE KEY%-%-%-%-%-", "a private key is being committed" },
  { "github token", "gh[pousr]_" .. rep("%w", 30), "looks like a GitHub token" },
  { "openai-style key", "sk%-" .. rep("%w", 30), "looks like an API secret key" },
  { "slack token", "xox[baprs]%-" .. rep("[%w%-]", 10), "looks like a Slack token" },
}

--- Assignments of a literal to something named like a secret: password = "hunter22"
local SECRET_NAMES = { "password", "passwd", "secret", "api_key", "apikey", "api%-key", "token", "private_key" }

--- Per extension: lines a debugger or a quick print leaves behind
---@type table<string, string[]>
local DEBUG = {
  js = { "console%.log%(", "debugger;?%s*$" },
  jsx = { "console%.log%(", "debugger;?%s*$" },
  ts = { "console%.log%(", "debugger;?%s*$" },
  tsx = { "console%.log%(", "debugger;?%s*$" },
  py = { "pdb%.set_trace%(", "breakpoint%(%)", "^%s*import pdb" },
  rb = { "binding%.pry", "byebug" },
  php = { "var_dump%(", "^%s*dd%(" },
  go = { "spew%.Dump%(" },
  rs = { "dbg!%(" },
}

---@param path string
---@return string
local function ext(path)
  return path:match "%.(%w+)$" or ""
end

---@param text string
---@return string? message
local function secret_in(text)
  for _, s in ipairs(SECRETS) do
    if text:find(s[2]) then
      return s[3]
    end
  end
  local low = text:lower()
  for _, name in ipairs(SECRET_NAMES) do
    -- name, then = or :, then a quoted literal of some length that is not obviously a placeholder
    local value = low:match(name .. "[%w_]*%s*[:=]+%s*[\"']([^\"']+)[\"']")
    if
      value
      and #value >= 8
      and not value:find "%s" -- a secret has no spaces: `password: "Password is required."` is a message
      and not value:find "^%$"
      and not value:find "{{"
      and not value:find "example"
      and not value:find "xxx"
      and not value:find "changeme"
    then
      return "a literal that looks like a " .. name:gsub("%%", "") .. " is being committed"
    end
  end
end

---@class AgentStaticFinding
---@field path string
---@field line integer
---@field severity integer
---@field message string

--- Findings in the added lines of `files`. `sensitive` = Lua patterns of paths that should never be committed
---@param files AgentDiffFile[]
---@param sensitive string[]?
---@return AgentStaticFinding[]
function M.check(files, sensitive)
  local out = {}
  local function add(path, line, severity, message)
    out[#out + 1] = { path = path, line = line, severity = severity, message = message }
  end
  for _, file in ipairs(files) do
    if file.status ~= "deleted" and file.status ~= "binary" then
      for _, pat in ipairs(sensitive or {}) do
        if file.path:find(pat) then
          add(file.path, 1, SEV.ERROR, "a sensitive file is staged (secrets, keys): unstage it")
          break
        end
      end
      local added = diff.added(file)
      if file.status == "new" and #added > 1500 then
        add(file.path, 1, SEV.INFO, ("a very large new file (%d lines): is it generated?"):format(#added))
      end
      local debug_patterns = DEBUG[ext(file.path)] or {}
      local is_test = file.path:find "_test%." or file.path:find "%.test%." or file.path:find "%.spec%."
      for _, l in ipairs(added) do
        if l.text:match "^<<<<<<< " or l.text:match "^>>>>>>> " or l.text == "=======" then
          add(file.path, l.n, SEV.ERROR, "a merge conflict marker is staged")
        else
          local secret = secret_in(l.text)
          if secret then
            add(file.path, l.n, SEV.ERROR, secret)
          elseif not is_test then
            for _, p in ipairs(debug_patterns) do
              if l.text:find(p) then
                add(file.path, l.n, SEV.WARN, "a debugging leftover is staged")
                break
              end
            end
          end
        end
      end
    end
  end
  return out
end

return M
